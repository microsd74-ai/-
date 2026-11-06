"""Run with Python 3 and PowerShell: python network_smoke.py /path/to/pwsh.
Uses a simulated UI Automation boundary; does not operate a real printer.
"""
import json
from pathlib import Path
import queue
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
PWSH = sys.argv[1] if len(sys.argv) > 1 else 'pwsh'
PROCESSES = []


def launch(script, *args):
    p = subprocess.Popen([PWSH, '-NoLogo', '-NoProfile', '-File', str(script), *args],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8')
    PROCESSES.append(p)
    messages = queue.Queue()
    def read():
        for line in p.stdout:
            try:
                messages.put(json.loads(line))
            except ValueError:
                messages.put({'type': 'diagnostic', 'detail': line.strip()})
    threading.Thread(target=read, daemon=True).start()
    return p, messages


def receive(q, match, seconds=12):
    end = time.monotonic() + seconds
    observed = []
    while time.monotonic() < end:
        try:
            item = q.get(timeout=max(0.01, end-time.monotonic()))
        except queue.Empty:
            break
        observed.append(item)
        if match(item):
            return item
    raise AssertionError(f'Expected response missing. Observed: {observed[-10:]}')


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def main():
    port = str(free_port())
    receiver = ROOT/'Monitor/ReceiveFleet.ps1'
    server, output = launch(receiver, '-Port', port)
    receive(output, lambda m: m.get('type') == 'listening')
    with tempfile.TemporaryDirectory() as temp:
        for i in (1, 2):
            folder = Path(temp)/str(i)
            folder.mkdir()
            shutil.copyfile(ROOT/'Agent/SendPrinter.ps1', folder/'SendPrinter.ps1')
            (folder/'ReadPrinter.ps1').write_text(
                "function Get-PrinterTelemetry { return @{line='OK|STATE|ESTIMATE|2026-11-05 15:30:00|10|100|2026-11-05 10:00:00|05:30:00'; extra=@{alarm='1/1:Test alarm'; temperature='24.67'; logTail='[2026-11-06 17:15:00] Warning: sample'; logState='tail'}} }\n",
                encoding='utf-8-sig')
            launch(folder/'SendPrinter.ps1', '-Server', '127.0.0.1', '-Port', port,
                   '-PrinterId', f'printer-{i}', '-PrinterName', f'Принтер {i}')
        seen = set()
        while len(seen) < 2:
            m = receive(output, lambda m: m.get('type') == 'telemetry')
            assert m['printed'] == '10' and m['total'] == '100'
            assert m['extra']['alarm'] == '1/1:Test alarm' and m['extra']['temperature'] == '24.67'
            assert m['name'] == 'Принтер ' + m['id'][-1]
            seen.add(m['id'])
        print('PASS: two actual senders, concurrent reception, Unicode names and field values')
        # A truncated UTF-8 codepoint across TCP writes must survive framing.
        payload = dict(m, id='fragmented', name='Станок Ж')
        data = (json.dumps(payload, ensure_ascii=False)+'\n').encode('utf-8')
        split = data.index('Ж'.encode('utf-8'))+1
        with socket.create_connection(('127.0.0.1', int(port))) as s:
            s.sendall(data[:split]); time.sleep(0.1); s.sendall(data[split:])
            got = receive(output, lambda v: v.get('id') == 'fragmented')
            assert got['name'] == 'Станок Ж'
        print('PASS: fragmented UTF-8 TCP message')
        for bad in (b'{bad json}\n', b'x'*16385):
            with socket.create_connection(('127.0.0.1', int(port))) as s:
                s.sendall(bad)
                s.settimeout(3)
                try:
                    assert s.recv(1) == b''
                except ConnectionResetError:
                    pass
        receive(output, lambda v: v.get('id') == 'printer-1')
        print('PASS: malformed and oversized clients disconnected; valid senders remain active')
        # Reader failures are transmitted, rather than displaying old readings as current.
        (Path(temp)/'1/ReadPrinter.ps1').write_text(
            "function Get-PrinterState { return 'ERROR|WINDOW_NOT_FOUND' }\n", encoding='utf-8-sig')
        # The running reader was loaded once. Restart only this test sender.
        sender = PROCESSES[1]; sender.terminate(); sender.wait(timeout=5)
        launch(Path(temp)/'1/SendPrinter.ps1', '-Server', '127.0.0.1', '-Port', port,
               '-PrinterId', 'printer-1', '-PrinterName', 'Принтер 1')
        error = receive(output, lambda v: v.get('id') == 'printer-1' and v.get('state') == 'reader_error')
        assert error['detail'] == 'ERROR|WINDOW_NOT_FOUND' and error['printed'] == ''
        print('PASS: reader error delivered with empty readings')
        server.terminate(); server.wait(timeout=5)
        time.sleep(2)
        server, output = launch(receiver, '-Port', port)
        receive(output, lambda v: v.get('type') == 'listening')
        seen = set()
        end = time.monotonic()+12
        while len(seen) < 2 and time.monotonic() < end:
            got = receive(output, lambda v: v.get('type') == 'telemetry')
            seen.add(got['id'])
        assert seen == {'printer-1', 'printer-2'}
        print('PASS: both senders reconnect after monitor restart')


if __name__ == '__main__':
    try:
        main()
    finally:
        for p in PROCESSES:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    p.kill(); p.wait()
