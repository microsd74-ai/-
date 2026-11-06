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
        assert item.get('type') != 'diagnostic', item
        observed.append(item)
        if match(item):
            return item
    raise AssertionError(f'Expected response missing. Observed: {observed[-10:]}')


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def main():
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        ports = [free_port(), free_port()]
        endpoints = [f'127.0.0.1:{port}' for port in ports]
        offline = f'127.0.0.1:{free_port()}'
        readers = []
        agents = []
        for i, port in enumerate(ports, 1):
            folder = temp/str(i)
            folder.mkdir()
            shutil.copyfile(ROOT/'Agent/SendPrinter.ps1', folder/'SendPrinter.ps1')
            reader = folder/'ReadPrinter.ps1'
            reader.write_text(
                "function Get-PrinterTelemetry { return @{line='OK|STATE|ESTIMATE|2026-11-05 15:30:00|10|100|2026-11-05 10:00:00|05:30:00'; extra=@{alarm='1/1:Test alarm'; temperature='24.67'; logTail='[2026-11-06 17:15:00] Warning: sample'; logState='tail'}} }\n",
                encoding='utf-8-sig')
            agent, aq = launch(folder/'SendPrinter.ps1', '-Port', str(port),
                               '-PrinterId', 'same-id', '-PrinterName', f'Принтер {i}')
            receive(aq, lambda m: m.get('type') == 'listening')
            agents.append((agent, aq, folder))
            readers.append(reader)
        config = temp/'targets.json'
        def targets(values):
            # Exercise concurrent config replacement; invalid content preserves existing sessions.
            config.write_text(json.dumps({'targets': values}), encoding='utf-8')
        targets(endpoints+[offline])
        monitor, output = launch(ROOT/'Monitor/ReceiveFleet.ps1', '-TargetsFile', str(config))
        def both(q):
            seen = set()
            deadline = time.monotonic()+15
            while len(seen) < 2 and time.monotonic() < deadline:
                m = receive(q, lambda v: v.get('type') == 'telemetry')
                assert m['id'] in endpoints
                assert m['printerId'] == 'same-id'
                assert m['name'] == 'Принтер ' + str(endpoints.index(m['id'])+1)
                if m['state'] == 'ok':
                    assert m['extra']['temperature'] == '24.67'
                seen.add(m['id'])
            assert seen == set(endpoints)
        both(output)
        print('PASS: monitor initiates connections to two agents; duplicate printer IDs stay in separate endpoint rows; offline target does not block others')
        targets([endpoints[0], offline])
        receive(agents[1][1], lambda v: v.get('type') == 'telemetry' and v.get('connections') == 0)
        targets(endpoints+[offline])
        receive(output, lambda v: v.get('id') == endpoints[1] and v.get('type') == 'telemetry')
        print('PASS: add/remove targets while monitor runs')
        config.write_text('{partial write', encoding='utf-8')
        receive(output, lambda v: v.get('type') == 'config_error')
        both(output)
        targets(endpoints)
        print('PASS: invalid settings update preserves established printer sessions')
        second, q2 = launch(ROOT/'Monitor/ReceiveFleet.ps1', '-TargetsFile', str(config))
        both(q2)
        receive(agents[0][1], lambda v: v.get('connections') == 2)
        second.terminate(); second.wait(timeout=5)
        receive(agents[0][1], lambda v: v.get('connections') == 1)
        both(output)
        print('PASS: multiple monitors can observe one agent independently')
        # Restart one agent while the other keeps producing telemetry.
        agents[0][0].terminate(); agents[0][0].wait(timeout=5)
        receive(output, lambda v: v.get('type') == 'connection' and v.get('id') == endpoints[0] and v.get('state') == 'disconnected')
        receive(output, lambda v: v.get('type') == 'telemetry' and v.get('id') == endpoints[1])
        readers[0].write_text("function Get-PrinterState { return 'ERROR|WINDOW_NOT_FOUND' }\n", encoding='utf-8-sig')
        new_agent, aq = launch(agents[0][2]/'SendPrinter.ps1', '-Port', str(ports[0]),
                               '-PrinterId', 'same-id', '-PrinterName', 'Принтер 1')
        error = receive(output, lambda v: v.get('type') == 'telemetry' and v.get('id') == endpoints[0] and v.get('state') == 'reader_error')
        assert error['detail'] == 'ERROR|WINDOW_NOT_FOUND' and error['printed'] == ''
        print('PASS: monitor reconnects after agent restart, reader errors delivered, other printer remains live')
        monitor.terminate(); monitor.wait(timeout=5)
        monitor, output = launch(ROOT/'Monitor/ReceiveFleet.ps1', '-TargetsFile', str(config))
        both(output)
        print('PASS: saved target list reconnects after monitor restart')
        # A simulated agent sends fragmented Unicode, then malformed data.
        fake = socket.socket()
        fake.bind(('127.0.0.1', 0)); fake.listen()
        fake_endpoint = f'127.0.0.1:{fake.getsockname()[1]}'
        payload = {'type':'telemetry','version':1,'id':'remote-id','name':'Станок Ж',
                   'state':'ok','detail':'','finishKind':'','finish':'','printed':'1','total':'2','start':'','duration':''}
        failures = []
        def fake_agent():
            try:
                fake.settimeout(12)
                with fake.accept()[0] as client:
                    data = (json.dumps(payload, ensure_ascii=False)+'\n').encode('utf-8')
                    cut = data.index('Ж'.encode('utf-8'))+1
                    client.sendall(data[:cut]); time.sleep(0.1); client.sendall(data[cut:])
                    time.sleep(0.5); client.sendall(b'{malformed json}\n')
                    client.settimeout(5)
                    assert client.recv(1) == b''
            except BaseException as e:
                failures.append(e)
            finally:
                fake.close()
        thread = threading.Thread(target=fake_agent, daemon=True); thread.start()
        targets(endpoints+[fake_endpoint])
        got = receive(output, lambda v: v.get('type') == 'telemetry' and v.get('id') == fake_endpoint)
        assert got['name'] == 'Станок Ж' and got['printerId'] == 'remote-id'
        receive(output, lambda v: v.get('type') == 'connection' and v.get('id') == fake_endpoint and v.get('state') == 'disconnected')
        thread.join(timeout=8)
        assert not thread.is_alive() and not failures, failures
        receive(output, lambda v: v.get('type') == 'telemetry' and v.get('id') == endpoints[1])
        print('PASS: fragmented UTF-8 handled; malformed peer disconnected without stopping other printers')


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
