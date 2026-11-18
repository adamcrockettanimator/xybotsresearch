from pathlib import Path
import wave, numpy as np, subprocess, concurrent.futures, csv, os, json, re, sys
ROOT=Path(__file__).resolve().parent.parent
FF=Path(os.environ.get('GRUDGE_FFMPEG',r'C:\Users\Adam\Documents\Codex\2026-10-19\the-x20\work\audio-match\ffmpeg\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe'))
if not FF.exists(): raise SystemExit('Set GRUDGE_FFMPEG to a working ffmpeg executable')
AUDIO=ROOT/'assets/Audio'; BARKS=AUDIO/'Dialog/Barks'
def bounds(path):
 with wave.open(str(path),'rb') as w:
  n,rate,width,ch=w.getnframes(),w.getframerate(),w.getsampwidth(),w.getnchannels(); raw=w.readframes(n)
 if width==2: samples=np.frombuffer(raw,dtype='<i2').astype(np.float32)/32768
 elif width==3:
  x=np.frombuffer(raw,dtype=np.uint8).reshape(-1,3).astype(np.int32);v=x[:,0]|x[:,1]<<8|x[:,2]<<16;samples=((v^0x800000)-0x800000).astype(np.float32)/8388608
 else: raise ValueError(f'Unsupported WAV width {width}: {path}')
 samples=np.max(np.abs(samples.reshape(-1,ch)),axis=1); block=max(1,rate//100)
 peaks=np.maximum.reduceat(samples,np.arange(0,n,block)) if n else np.array([])
 active=np.flatnonzero(peaks>=10**(-65/20))
 if not len(active): return 0.0,n/rate,n/rate
 start=max(0.0,active[0]*block/rate-0.15); end=min(n/rate,(active[-1]+1)*block/rate+0.15)
 return start,end,n/rate

def convert(path):
 start,end,dur=bounds(path); out=path.with_suffix('.ogg'); tmp=out.with_suffix('.tmp.ogg')
 cmd=[str(FF),'-hide_banner','-loglevel','error','-nostdin','-y','-i',str(path),'-af',f'atrim=start={start:.6f}:end={end:.6f},asetpts=PTS-STARTPTS','-ac','1','-ar','32000','-c:a','libvorbis','-q:a','4',str(tmp)]
 subprocess.run(cmd,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE);os.replace(tmp,out)
 return (path.relative_to(ROOT).as_posix(),round(dur,4),round(start,4),round(dur-end,4),round(end-start,4),path.stat().st_size,out.stat().st_size)
if __name__ == '__main__':
	files=sorted(BARKS.rglob('*.wav'))
	if '--only-missing' in sys.argv:files=[p for p in files if not p.with_suffix('.ogg').exists()]
	with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
	 records=[]
	 for i,row in enumerate(pool.map(convert,files),1):
	  records.append(row)
	  if i%100==0:print(f'Converted {i}/{len(files)} dialogue clips',flush=True)
	report=ROOT/'docs/audio_optimization_report.csv'
	with report.open('w',encoding='utf8',newline='') as f:
	 w=csv.writer(f);w.writerow(['source','original_seconds','trim_start_seconds','trim_end_seconds','output_seconds','wav_bytes','ogg_bytes']);w.writerows(records)
	print('DIALOGUE_RESULT',len(records),sum(r[1] for r in records),sum(r[2]+r[3] for r in records),sum(r[5] for r in records),sum(r[6] for r in records),flush=True)
