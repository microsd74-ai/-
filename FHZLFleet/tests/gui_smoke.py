"""Linux GTK2 UI smoke test. Requires Xvfb DISPLAY, xdotool and ImageMagick import.
Runs an isolated binary copy with synthetic read-only telemetry, not real printers.
Usage: python gui_smoke.py /path/to/Monitor /path/to/xdotool /tmp/screenshots
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

binary, xdotool, screenshots = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
screenshots.mkdir(parents=True, exist_ok=True)

def xdo(*args):
    return subprocess.check_output([xdotool, *map(str,args)], stderr=subprocess.DEVNULL, text=True).strip()

def window(title, timeout=10):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        try:
            ids=xdo('search','--onlyvisible','--name','^'+title+'$').splitlines()
            if ids: return ids[-1]
        except subprocess.CalledProcessError: pass
        time.sleep(.1)
    raise AssertionError('Window missing: '+title)

def visible(title):
    try: window(title,.3); return True
    except AssertionError: return False

def click(w,x,y):
    xdo('windowfocus','--sync',w); xdo('mousemove','--window',w,x,y); xdo('click','1'); time.sleep(.2)

def field(w,x,y,value):
    click(w,x,y); xdo('key','ctrl+a'); xdo('type','--clearmodifiers','--delay','1',value)

def shot(w,name):
    time.sleep(.3)
    subprocess.run(['import','-window',w,str(screenshots/name)],check=True)

with tempfile.TemporaryDirectory(prefix='fhzl-ui-') as temp:
    root=Path(temp); app=root/'Monitor'; shutil.copy2(binary,app)
    (root/'ReceiveFleet.ps1').write_text('# Test fixture: executable stub provides telemetry.\n')
    config=root/'Monitor.targets.json'
    data={'targets':['127.0.0.1:5055','127.0.0.2:5055'], 'printers':[
        {'name':'FHZL PMMA','host':'127.0.0.1','port':5055},
        {'name':'FHZL second','host':'127.0.0.2','port':5055}]}
    config.write_text(json.dumps(data))
    stub=root/'win/System32/WindowsPowerShell/v1.0/powershell.exe'; stub.parent.mkdir(parents=True)
    stub.write_text('''#!/usr/bin/env python3
import json,time
for endpoint in ['127.0.0.1:5055','127.0.0.2:5055']:
 print(json.dumps({'type':'connection','id':endpoint,'state':'connected'}),flush=True)
while True:
 for i in (1,2):
  print(json.dumps({'type':'telemetry','version':1,'id':f'127.0.0.{i}:5055','name':'Agent name',
   'state':'ok','detail':'','printed':'125','total':'500','finish':'2026-11-06 20:30:00','finishKind':'ESTIMATE',
   'duration':'03:15:00','extra':{'alarm':'E4.2: Sand box squeezes cylinder Alarm' if i==1 else '',
    'file':'example_0538.tif','modes':'MainManual','axes':'X: 0.00; Y: 0.00; PS: -5.00',
    'temperature':'26.65' if i==1 else '22.55','humidity':'32.53','layerSeconds':'48','layerAverage':'20.6',
    'logState':'tail','logTail':'[2026-11-06 18:44:28] Info: synthetic test event'}}),flush=True)
 time.sleep(1)
'''); stub.chmod(0o755)
    literal=root/('win'+chr(92)+'System32'+chr(92)+'WindowsPowerShell'+chr(92)+'v1.0'+chr(92)+'powershell.exe'); shutil.copy2(stub,literal)
    env=os.environ.copy(); env['SystemRoot']=str(root/'win')
    log=open(screenshots/'process.log','w')
    process=subprocess.Popen([str(app)],env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        main=window('FHZL — общий монитор'); time.sleep(2)
        shot(main,'main.png')
        # A first visit creates a password; no default password is shipped.
        click(main,970,36); setup=window('Создать пароль управления')
        field(setup,180,100,'short'); field(setup,180,174,'short'); click(setup,350,282)
        assert visible('Создать пароль управления') and not (root/'Monitor.admin.json').exists()
        click(setup,220,282); assert not (root/'Monitor.admin.json').exists()
        click(main,970,36); setup=window('Создать пароль управления')
        field(setup,180,100,'test-admin-pass'); field(setup,180,174,'test-admin-pass')
        click(setup,350,282); admin=window('Управление принтерами')
        field(admin,300,296,'FHZL workshop'); click(admin,310,444)
        assert json.loads(config.read_text())['printers'][0]['name']=='FHZL workshop'
        field(admin,300,296,'FHZL third'); field(admin,300,342,'127.0.0.3'); field(admin,300,388,'5055')
        click(admin,100,444); assert len(json.loads(config.read_text())['targets'])==3
        shot(admin,'management.png')
        click(admin,520,444); confirm=window('Удалить принтер'); xdo('windowfocus',confirm); xdo('key','Return'); time.sleep(.4)
        assert len(json.loads(config.read_text())['targets'])==2
        click(admin,555,534)
        print('PASS: first-run password setup; admin rename, add and delete persist')
        saved=config.read_bytes()
        click(main,970,36); login=window('Вход в управление')
        field(login,180,100,'wrong-password'); click(login,350,208)
        assert visible('Вход в управление') and not visible('Управление принтерами') and config.read_bytes()==saved
        field(login,180,100,'test-admin-pass'); shot(login,'login.png'); click(login,350,208)
        admin=window('Управление принтерами')
        click(admin,120,534); change=window('Сменить пароль')
        field(change,180,100,'test-admin-pass'); field(change,180,174,'second-admin-pass'); field(change,180,248,'second-admin-pass')
        click(change,350,356); time.sleep(.3); click(admin,555,534)
        click(main,970,36); login=window('Вход в управление')
        field(login,180,100,'test-admin-pass'); click(login,350,208)
        assert visible('Вход в управление') and not visible('Управление принтерами')
        field(login,180,100,'second-admin-pass'); click(login,350,208); admin=window('Управление принтерами'); click(admin,555,534)
        record=json.loads((root/'Monitor.admin.json').read_text())
        assert record['hash']==hashlib.pbkdf2_hmac('sha256',b'second-admin-pass',bytes.fromhex(record['salt']),record['iterations']).hex()
        print('PASS: wrong password blocks management; correct password opens it; changed password invalidates old password')
        click(main,270,36); xdo('key','Down','Return'); time.sleep(.3); shot(main,'second-printer.png')
        process.terminate(); process.wait(timeout=5)
        process=subprocess.Popen([str(app)],env=env,stdout=log,stderr=subprocess.STDOUT)
        main=window('FHZL — общий монитор'); time.sleep(1)
        click(main,970,36); login=window('Вход в управление')
        assert not visible('Создать пароль управления')
        field(login,180,100,'second-admin-pass'); click(login,350,208); admin=window('Управление принтерами')
        assert json.loads(config.read_text())['printers'][0]['name']=='FHZL workshop'
        click(admin,555,534)
        print('PASS: printer selection, saved names and password survive process restart')
    finally:
        if process.poll() is None: process.terminate(); process.wait(timeout=5)
        log.close()
