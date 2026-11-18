from pathlib import Path
import csv,datetime,hashlib,json,math,os,wave,zipfile
import numpy as np

root=Path.cwd().resolve()
bank=json.loads((root/'assets/Audio/Dialog/bark_bank.json').read_text(encoding='utf8'))
paths=sorted({(root / entry['path'].removeprefix('res://')).with_suffix('.wav').resolve() for voice in bank.values() for lines in voice.values() for entry in lines})
audio_root=(root/'assets/Audio/Dialog/Barks').resolve()
if not all(p.is_relative_to(audio_root) and p.is_file() for p in paths):
 raise RuntimeError('All bark paths must exist inside the game bark directory')
backup_dir=Path(r'D:\Godot\xybotsResearch\Audio\Dialog\Game bark backups')
backup_dir.mkdir(parents=True,exist_ok=True)
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup=backup_dir/('game-barks-before-normalization-'+stamp+'.zip')
manifest=[]
with zipfile.ZipFile(backup,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=3) as archive:
 for path in paths:
  rel=path.relative_to(root).as_posix()
  data=path.read_bytes()
  archive.writestr(rel,data)
  manifest.append({'path':rel,'sha256':hashlib.sha256(data).hexdigest()})
 archive.writestr('backup-manifest.json',json.dumps(manifest,indent=2))
 archive.writestr('bark_bank.json',(root/'assets/Audio/Dialog/bark_bank.json').read_bytes())
with zipfile.ZipFile(backup) as archive:
 if archive.testzip() is not None or len(archive.namelist()) != len(paths)+2:
  raise RuntimeError('Backup failed integrity verification; no audio was changed')
print('Verified backup:',backup,flush=True)
records=[]
for path in paths:
 with wave.open(str(path),'rb') as reader:
  channels,width,rate,frames=reader.getnchannels(),reader.getsampwidth(),reader.getframerate(),reader.getnframes()
  data=reader.readframes(frames)
 if width==2:
  samples=np.frombuffer(data,dtype='<i2').astype(np.float64)/32768.0
 elif width==3:
  bits=np.frombuffer(data,dtype=np.uint8).reshape(-1,3).astype(np.int32)
  bits=bits[:,0]|bits[:,1]<<8|bits[:,2]<<16
  samples=((bits^0x800000)-0x800000).astype(np.float64)/8388608.0
 else: raise ValueError(f'Unsupported {width}-byte PCM: {path}')
 audio=samples.reshape(-1,channels)
 block_size=max(1,rate//10)
 powers=[float(np.mean(audio[i:i+block_size]**2)) for i in range(0,len(audio),block_size) if len(audio[i:i+block_size])>=block_size//2]
 maximum=max(powers,default=0.0)
 active=[p for p in powers if p >= max(maximum*0.001,1e-9)]
 rms=math.sqrt(sum(active)/len(active)) if active else 0.0
 peak=float(np.max(np.abs(audio))) if audio.size else 0.0
 if not rms or not peak:
  records.append([path.relative_to(root).as_posix(),'silent','','',''])
  continue
 # Active-block RMS reduces the effect of silence at clip boundaries. Apply
 # only constant gain, retaining dynamics; never clip or boost over 24 dB.
 gain=min(10**(24/20),10**(-20/20)/rms,10**(-1/20)/peak)
 scaled=np.clip(samples*gain,-1.0,1.0-1.0/(2**(8*width-1)))
 if width==2:
  encoded=np.rint(scaled*32768.0).astype('<i2').tobytes()
 else:
  val=np.rint(scaled*8388608.0).astype(np.int32)
  output=np.empty((len(val),3),dtype=np.uint8)
  output[:,0]=val&255;output[:,1]=(val>>8)&255;output[:,2]=(val>>16)&255
  encoded=output.tobytes()
 temp=path.with_suffix('.normalize_tmp')
 with wave.open(str(temp),'wb') as writer:
  writer.setnchannels(channels);writer.setsampwidth(width);writer.setframerate(rate);writer.writeframes(encoded)
 os.replace(temp,path)
 records.append([path.relative_to(root).as_posix(),round(20*math.log10(rms),2),round(20*math.log10(rms*gain),2),round(20*math.log10(gain),2),round(20*math.log10(peak*gain),2)])
report=backup_dir/('normalization-report-'+stamp+'.csv')
with report.open('w',newline='',encoding='utf8') as output:
 writer=csv.writer(output);writer.writerow(['path','active_rms_before_dbfs','active_rms_after_dbfs','gain_db','peak_after_dbfs']);writer.writerows(records)
levels=[r[2] for r in records if isinstance(r[2],float)]
print('Normalized',len(paths),'files; active RMS percentiles:',np.percentile(levels,[0,10,50,90,100]).round(1).tolist(),flush=True)
print('Below -26 dBFS:',sum(level < -26 for level in levels),'Report:',report,flush=True)

# Rebuild the game-facing compressed copies and their scheduling durations.
from optimize_dialog_audio import convert
durations={}
for path in paths:
 result=convert(path)
 durations['res://'+path.relative_to(root).with_suffix('.ogg').as_posix()]=result[4]
for voice in bank.values():
 for lines in voice.values():
  for entry in lines:
   entry['duration_seconds']=durations[entry['path']]
(root/'assets/Audio/Dialog/bark_bank.json').write_text(json.dumps(bank,indent=2,ensure_ascii=False),encoding='utf8')
print('Regenerated optimized dialogue copies and durations',flush=True)
