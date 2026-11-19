"""Validate the editable bark CSV and rebuild Godot's dialogue bank.

Usage from the project folder: python tools/apply_bark_catalog.py --check
                              python tools/apply_bark_catalog.py
The original actor recordings are never edited. Newly used game copies are
normalized once; existing normalized game copies are preserved.
"""
import csv,hashlib,json,math,re,shutil,sys,unicodedata,wave,zipfile,xml.etree.ElementTree as ET
from pathlib import Path
import numpy as np
PROJECT=Path(__file__).resolve().parents[1]
SOURCE=Path(r'D:\Godot\xybotsResearch\Audio\Dialog\Dialog clips - review')
CATALOG=PROJECT/'assets/Audio/Dialog/bark_catalog.csv'
SEED=PROJECT/'tools/bark_bank_seed.json'
BANK=PROJECT/'assets/Audio/Dialog/bark_bank.json'
ALIASES={'hitreact':'hit','hit_react':'hit','reloading':'reload','taunt':'taunt','postkill':'victory','post_kill':'victory','allyfall':'ally_fall','searching':'search','alert':'hearing','killed_player':'kill_player','player_hit':'hit_player','charging':'charge','killed':'death'}
ALLOWED=set('hearing shot ally_fall attacking reply_attack charge flank flee hiding hit hit_player investigate death victory lost_contact player_cover player_reload player_roll player_spotted combat first_sighting kill_player reload search cover taunt'.split())
def clean(s):
 s=unicodedata.normalize('NFKD',s.lower()).replace('’',"'")
 return re.sub(r'\s+',' ',re.sub(r'[^a-z0-9 ]','',s)).strip()
def normalize_copy(source,dest):
 with wave.open(str(source),'rb') as reader:
  ch,width,rate,frames=reader.getnchannels(),reader.getsampwidth(),reader.getframerate(),reader.getnframes();raw=reader.readframes(frames)
 if width==2:x=np.frombuffer(raw,'<i2').astype(np.float64)/32768
 elif width==3:
  a=np.frombuffer(raw,np.uint8).reshape(-1,3).astype(np.int32);v=a[:,0]|a[:,1]<<8|a[:,2]<<16;x=((v^0x800000)-0x800000).astype(np.float64)/8388608
 else:raise ValueError(f'Unsupported PCM width {width}: {source}')
 audio=x.reshape(-1,ch);size=rate//10;blocks=[float(np.mean(audio[i:i+size]**2)) for i in range(0,len(audio),size) if len(audio[i:i+size])>=size//2]; peak=max(blocks,default=0.0);active=[v for v in blocks if v>=max(peak*.001,1e-9)];rms=math.sqrt(sum(active)/len(active)) if active else 0.;peak=float(np.max(np.abs(x))) if x.size else 0.
 gain=min(10**(24/20),10**(-20/20)/rms,10**(-1/20)/peak) if rms and peak else 1.;x=np.clip(x*gain,-1.,1.-1./(2**(8*width-1)))
 if width==2:raw=np.rint(x*32768).astype('<i2').tobytes()
 else:
  v=np.rint(x*8388608).astype(np.int32);o=np.empty((len(v),3),dtype=np.uint8);o[:,0]=v&255;o[:,1]=(v>>8)&255;o[:,2]=(v>>16)&255;raw=o.tobytes()
 dest.parent.mkdir(parents=True,exist_ok=True)
 with wave.open(str(dest),'wb') as out:out.setnchannels(ch);out.setsampwidth(width);out.setframerate(rate);out.writeframes(raw)
seed=json.loads(SEED.read_text(encoding='utf8'));prior={};by_source={};phrase_rules={}
for actor,cats in seed.items():
 for cat,entries in cats.items():
  for e in entries:
   prior[(actor,e['source'],cat)]=e;by_source.setdefault((actor,e['source']),e)
   phrase=clean(Path(e['source']).stem.split(' - ',1)[-1])
   phrase_rules.setdefault((phrase,cat),[]).append(e)
def read_xlsx(path):
 # Read ordinary Excel/Google-Sheets value cells without requiring Excel or an
 # additional Python package. Formula cells are intentionally rejected.
 ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
     'r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
     'p':'http://schemas.openxmlformats.org/package/2006/relationships'}
 result=[]
 with zipfile.ZipFile(path) as z:
  shared=[]
  if 'xl/sharedStrings.xml' in z.namelist():
   shared=[''.join(x.itertext()) for x in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si',ns)]
  book=ET.fromstring(z.read('xl/workbook.xml'))
  relationships=ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
  links={x.get('Id'):x.get('Target') for x in relationships.findall('p:Relationship',ns)}
  for sheet in book.findall('m:sheets/m:sheet',ns):
   if sheet.get('name','').lower() not in ('zach','adam','rowan','devin'):continue
   target=links[sheet.get('{'+ns['r']+'}id')].lstrip('/')
   if not target.startswith('xl/'):target='xl/'+target
   root=ET.fromstring(z.read(target));headers=None
   for row in root.findall('m:sheetData/m:row',ns):
    cells={}
    for cell in row.findall('m:c',ns):
     ref=re.match(r'([A-Z]+)',cell.get('r',''))
     if not ref:continue
     col=0
     for c in ref.group(1):col=col*26+ord(c)-64
     if cell.find('m:f',ns) is not None:raise ValueError(f'Formula not supported in {sheet.get("name")}!{cell.get("r")}')
     value=cell.find('m:v',ns);typ=cell.get('t','')
     if typ=='inlineStr':text=''.join(cell.find('m:is',ns).itertext()) if cell.find('m:is',ns) is not None else ''
     elif value is None:text=''
     elif typ=='s':text=shared[int(value.text)]
     else:text=value.text or ''
     cells[col-1]=text
    if headers is None:
     if 'actor' in cells.values() and 'file' in cells.values() and 'tags' in cells.values():headers={v:k for k,v in cells.items()}
     continue
    record={name:cells.get(column,'') for name,column in headers.items()}
    if record.get('file','').strip():result.append(record)
   if headers is None:raise ValueError(f'No catalog header found on {sheet.get("name")}')
 return result

xlsx_path=None
if '--xlsx' in sys.argv:
 ix=sys.argv.index('--xlsx')
 if ix+1>=len(sys.argv):raise SystemExit('Provide a downloaded .xlsx after --xlsx')
 xlsx_path=Path(sys.argv[ix+1]).resolve();rows=read_xlsx(xlsx_path)
else:
 with CATALOG.open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
parsed=[];seen=set();errors=[]
for i,row in enumerate(rows,2):
 actor=row.get('actor','').strip().lower();file=row.get('file','').strip();key=(actor,file)
 if actor not in ('zach','adam','rowan','devin') or Path(file).name!=file or key in seen or not (SOURCE/actor/file).is_file():errors.append(f'Row {i}: invalid actor, duplicate, or missing recording');continue
 seen.add(key);tags=[]
 tag_text=re.sub(r'#player\s+spotted\b','#player_spotted',row.get('tags','').strip(),flags=re.I)
 for token in re.split(r'[\s,;]+',tag_text):
  if not token:continue
  tag=token.lstrip('#').lower().replace('-','_');tag=ALIASES.get(tag,tag)
  if tag not in ALLOWED:errors.append(f'Row {i}: unknown tag {token}')
  elif tag not in tags:tags.append(tag)
 try:
  weight=float(row.get('weight','1') or 1);duration=float(row.get('duration_seconds','0') or 0)
  if not math.isfinite(weight) or weight<0 or weight>100 or not math.isfinite(duration) or duration<0:raise ValueError()
  min_override=int(row['min_enemies']) if row.get('min_enemies','').strip() else None
  max_override=int(row['max_enemies']) if row.get('max_enemies','').strip() else None
  if (min_override is not None and min_override<1) or (max_override is not None and max_override<1) or (min_override and max_override and min_override>max_override):raise ValueError()
 except ValueError:errors.append(f'Row {i}: invalid weight, duration or enemy count');continue
 phrase=clean(Path(file).stem.split(' - ',1)[-1])
 group_line=bool(re.search(r'\b(we|our|us|lets|yall|you guys)\b',phrase) or re.search(r"\bwe['’](re|ve|ll|d)\b",file.lower()))
 if max_override == 1 and tags and (group_line or any(t in ('flank','charge') for t in tags)):
  errors.append(f'Row {i}: group/coordinated line cannot have max_enemies 1');continue
 repeat=row.get('repeatable','no').strip().lower()
 if repeat not in ('yes','no','true','false','1','0'):errors.append(f'Row {i}: repeatable must be yes or no');continue
 parsed.append((actor,file,tags,weight,repeat in ('yes','true','1'),min_override,max_override,duration))
# Mandatory reactions must remain available even when a single outlaw is
# present. Short repeatable choices prevent round-wide history from exhausting
# hit, death or first-sighting reactions across enemies with the same voice.
for actor in ('zach','adam','rowan','devin'):
 for tag in ('hit','death','first_sighting','kill_player'):
  eligible=[]
  for a,file,tags,weight,repeat,min_override,max_override,duration in parsed:
   if a!=actor or tag not in tags or weight<=0 or (min_override is not None and min_override>1):continue
   phrase=clean(Path(file).stem.split(' - ',1)[-1])
   if re.search(r'\b(we|our|us|lets|yall|you guys)\b',phrase) or re.search(r"\bwe['’](re|ve|ll|d)\b",file.lower()):continue
   prior_min=int(prior.get((actor,file,tag),{}).get('min_enemies',1))
   if tag not in ('first_sighting','kill_player') and min_override is None and prior_min>1:continue
   eligible.append(repeat)
  if not eligible or (tag in ('hit','death','first_sighting') and not any(eligible)):
   errors.append(f'{actor} needs a solo-eligible {tag} line with positive weight' + (' and a repeatable short option' if tag in ('hit','death','first_sighting') else ''))
expected={(actor,f.name) for actor in ('zach','adam','rowan','devin') for f in (SOURCE/actor).glob('*.wav')}
missing=expected-seen
if missing:
 errors.append(f'{len(missing)} recording row(s) missing; keep the row and leave tags blank to disable it')
if errors:
 print('\n'.join(errors[:50]));raise SystemExit(f'{len(errors)} catalog error(s); bank not changed')
print(f'Validated {len(parsed)} recordings; {sum(bool(r[2]) for r in parsed)} tagged, {sum(not r[2] for r in parsed)} unassigned.')
if '--check' in sys.argv:raise SystemExit(0)
from optimize_dialog_audio import convert, bounds
new={a:{} for a in seed};copied=0
for actor,file,tags,weight,repeat,min_override,max_override,duration in parsed:
 if not tags:continue
 old=by_source.get((actor,file));source=SOURCE/actor/file
 if old and (PROJECT/old['path'].removeprefix('res://')).is_file():path=old['path']
 else:
  digest=hashlib.sha256(file.encode('utf8')).hexdigest()[:16];dest=PROJECT/'assets/Audio/Dialog/Barks'/actor/('catalog_'+digest+'.wav')
  if not dest.exists():normalize_copy(source,dest);copied+=1
  result=convert(dest)
  path='res://'+dest.with_suffix('.ogg').relative_to(PROJECT).as_posix()
  duration=result[4]
 if old and path.endswith('.wav'):
  wav=PROJECT/path.removeprefix('res://')
  result=convert(wav) if not wav.with_suffix('.ogg').exists() else None
  path=path[:-4]+'.ogg'
  duration=result[4] if result is not None else round(bounds(wav)[1]-bounds(wav)[0],4)
 spoken=clean(Path(file).stem.split(' - ',1)[-1]);line_id=old.get('id',spoken) if old else spoken
 for tag in tags:
  previous=prior.get((actor,file,tag),{})
  minimum=int(previous.get('min_enemies',1));maximum=int(previous.get('max_enemies',999))
  if not previous:
   # Alternative takes with the same wording inherit the safest existing
   # event constraints; no actor may announce a group line while alone.
   known=phrase_rules.get((spoken,tag),[])
   if known:
    minimum=max(int(e.get('min_enemies',1)) for e in known)
    maximum=min(int(e.get('max_enemies',999)) for e in known)
  if tag in ('first_sighting','kill_player') and not re.search(r'\b(we|our|us|lets|yall)\b',spoken):minimum=1
  if min_override is not None:minimum=min_override
  if max_override is not None:maximum=max_override
  # Group language and coordinated maneuvers remain unsafe when alone, even
  # if the spreadsheet accidentally requests a lower minimum.
  if tag in ('flank','charge') or re.search(r'\b(we|our|us|lets|yall|you guys)\b',spoken) or re.search(r"\bwe['’](re|ve|ll|d)\b",file.lower()):minimum=max(minimum,2)
  if minimum>maximum:raise ValueError(f'Conflicting limits for {actor}: {file} #{tag}')
  item={'path':path,'id':line_id,'repeatable':repeat,'min_enemies':minimum,'max_enemies':maximum,'source':file,'weight':weight,'duration_seconds':duration}
  if 'sheet_row' in previous:item['sheet_row']=previous['sheet_row']
  new[actor].setdefault(tag,[]).append(item)
temp=BANK.with_suffix('.json.tmp');temp.write_text(json.dumps(new,indent=2,ensure_ascii=False),encoding='utf8');temp.replace(BANK)
preset=PROJECT/'export_presets.cfg';lines=preset.read_text(encoding='utf8').splitlines(keepends=True);paths=sorted({e['path'] for c in new.values() for es in c.values() for e in es})
for i,line in enumerate(lines):
 if line.startswith('export_files=PackedStringArray('):
  add=[p for p in paths if '"'+p+'"' not in line]
  if add:lines[i]=line.rstrip('\r\n')[:-1]+', '+', '.join('"'+p+'"' for p in add)+')\n'
  break
preset.write_text(''.join(lines),encoding='utf8')
if xlsx_path is not None:
 # Keep the checked spreadsheet as the canonical CSV for future rebuilds.
 import datetime
 backup=CATALOG.with_name('bark_catalog_before_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'.csv.bak')
 shutil.copy2(CATALOG,backup)
 columns=['actor','file','tags','weight','repeatable','min_enemies','max_enemies','duration_seconds','matching']
 with CATALOG.open('w',encoding='utf-8-sig',newline='') as out:
  writer=csv.DictWriter(out,fieldnames=columns,extrasaction='ignore');writer.writeheader();writer.writerows(rows)
 print(f'Updated CSV; previous copy saved at {backup}')
print(f'Built {sum(len(v) for c in new.values() for v in c.values())} tagged entries; {copied} new normalized game copies; {len(paths)} exported recordings.')
