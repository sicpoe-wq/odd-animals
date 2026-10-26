import re,glob, json, urllib.request, urllib.parse, concurrent.futures as cf, sys
OVR={'Olm':'Proteus_anguinus_Postojnska_Jama_Slovenija.jpg','Vaquita':'Vaquita6_Olson_NOAA.jpg'}
rows=[]
for f in sorted(glob.glob('data/a*.txt')):
    for line in open(f):
        line=line.strip()
        if not line: continue
        p=line.split('|')
        assert len(p)==5,(f,line[:50])
        facts=[x.strip() for x in p[4].split(';;') if x.strip()]
        assert 3<=len(facts)<=5,(p[0],len(facts))
        rows.append(dict(name=p[0],scientific=p[1],wiki=p[2],habitat=p[3],facts=facts))
def get(r):
    url='https://en.wikipedia.org/api/rest_v1/page/summary/'+urllib.parse.quote(r['wiki'].replace(' ','_'),safe='')
    req=urllib.request.Request(url,headers={'User-Agent':'OddAnimalsBuild/1.0 (github.com/sicpoe-wq)'})
    try:
        d=json.load(urllib.request.urlopen(req,timeout=20))
    except Exception as e:
        return r,None,str(e)
    return r,d,None
out=[];bad=[]
with cf.ThreadPoolExecutor(8) as ex:
    for r,d,e in ex.map(get,rows):
        if e or d.get('type')!='standard' or not d.get('thumbnail'):
            bad.append((r['name'],r['wiki'],e or d.get('type'),bool(d and d.get('thumbnail')))); continue
        r['wiki']=d['titles']['canonical'].replace('_',' ')
        r['thumb']=d['thumbnail']['source']
        r['file']=OVR.get(r['name']) or (urllib.parse.unquote(re.search(r'/thumb/./../([^/]+)/',d['thumbnail']['source']).group(1)) if '/thumb/' in d['thumbnail']['source'] else None)
        out.append(r)
import time
def api(q):
    for k in range(6):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(q,headers={'User-Agent':'OddAnimalsBuild/1.0 (github.com/sicpoe-wq)'}),timeout=30))
        except urllib.error.HTTPError as e:
            if e.code==429: time.sleep(5*(k+1)); continue
            raise
files=[r['file'] for r in out if r.get('file')]
info={}
for i in range(0,len(files),40):
    chunk=files[i:i+40]
    q='https://en.wikipedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url&iiurlwidth=960&titles='+urllib.parse.quote('|'.join('File:'+f for f in chunk))
    d=api(q); norm={n['to']:n['from'] for n in d['query'].get('normalized',[])}
    for p in d['query']['pages'].values():
        t=norm.get(p['title'],p['title'])
        if 'imageinfo' in p: info[t[5:]]=p['imageinfo'][0]['thumburl']
    time.sleep(1)
for r in out:
    f=r.get('file'); u=info.get(f) if f else None
    if u and r['name'] in OVR: r['img']=u
    elif u and '/thumb/' in u and not f.lower().endswith('.png'): r['img']=u
    else: r['img']=r['thumb']
    if f and not u: print('noinfo',r['name'],f)
names=[r['name'] for r in out]
dups={n for n in names if names.count(n)>1}
print('ok',len(out),'bad',bad,'dups',dups)
for r in out: print(r['name'],'->',r['wiki'])
json.dump([{k:r[k] for k in ('name','scientific','wiki','habitat','facts','img','thumb')} for r in out],open('../assets/animals.json','w'),ensure_ascii=False,indent=1)
