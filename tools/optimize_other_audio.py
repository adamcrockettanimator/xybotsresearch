from pathlib import Path
import wave,subprocess,os,csv,concurrent.futures
from optimize_dialog_audio import ROOT,AUDIO,FF,bounds

def process_wav(p):
 with wave.open(str(p),'rb') as w: rate=w.getframerate(); width=w.getsampwidth(); original=w.getnframes()/rate
 start,end,_=bounds(p); tmp=p.with_suffix('.optimized.tmp.wav'); codec='pcm_s24le' if width==3 else 'pcm_s16le'
 cmd=[str(FF),'-hide_banner','-loglevel','error','-nostdin','-y','-i',str(p),'-af',f'atrim=start={start:.6f}:end={end:.6f},asetpts=PTS-STARTPTS','-ac','1','-ar',str(rate),'-c:a',codec,str(tmp)]
 before=p.stat().st_size;subprocess.run(cmd,check=True,stderr=subprocess.PIPE)
 with wave.open(str(tmp),'rb') as r: ch,bits,hz,data=r.getnchannels(),r.getsampwidth(),r.getframerate(),r.readframes(r.getnframes())
 with wave.open(str(tmp),'wb') as w: w.setnchannels(ch);w.setsampwidth(bits);w.setframerate(hz);w.writeframes(data)
 os.replace(tmp,p)
 return [p.relative_to(ROOT).as_posix(),round(original,4),round(start,4),round(original-end,4),before,p.stat().st_size]
if (ROOT/'docs/audio_sfx_optimization_report.csv').exists():
 raise SystemExit('Audio has already been optimized; restore verified originals before running again.')
files=sorted((AUDIO/'SFX').rglob('*.wav'))
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
 rows=[]
 for i,r in enumerate(pool.map(process_wav,files),1):
  rows.append(r)
  if i%100==0:print('Processed SFX',i,'/',len(files),flush=True)
with (ROOT/'docs/audio_sfx_optimization_report.csv').open('w',encoding='utf8',newline='') as f:
 w=csv.writer(f);w.writerow(['path','original_seconds','trim_start_seconds','trim_end_seconds','before_bytes','after_bytes']);w.writerows(rows)
print('SFX_RESULT',len(rows),sum(r[1] for r in rows),sum(r[2]+r[3] for r in rows),sum(r[4] for r in rows),sum(r[5] for r in rows),flush=True)
# Music uses compressed MP3/Vorbis and loops: retain the whole track, convert
# channels without changing its sample rate, and preserve a high-quality encode.
for p in sorted((AUDIO/'Music').glob('*')):
 if p.suffix.lower() not in ['.wav','.mp3','.ogg']:continue
 tmp=p.with_name(p.stem+'.optimized.tmp'+p.suffix);before=p.stat().st_size
 codec=['-c:a','libmp3lame','-q:a','2'] if p.suffix.lower()=='.mp3' else (['-c:a','libvorbis','-q:a','5'] if p.suffix.lower()=='.ogg' else ['-c:a','pcm_s24le'])
 subprocess.run([str(FF),'-hide_banner','-loglevel','error','-nostdin','-y','-i',str(p),'-ac','1',*codec,str(tmp)],check=True,stderr=subprocess.PIPE)
 if p.suffix.lower()=='.wav':
  with wave.open(str(tmp),'rb') as r: ch,bits,hz,data=r.getnchannels(),r.getsampwidth(),r.getframerate(),r.readframes(r.getnframes())
  with wave.open(str(tmp),'wb') as w: w.setnchannels(ch);w.setsampwidth(bits);w.setframerate(hz);w.writeframes(data)
 os.replace(tmp,p)
 print('MUSIC_RESULT',p.name,before,p.stat().st_size,flush=True)
