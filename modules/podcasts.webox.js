WeBox.define({
 api:"1.3",category:"podcast",id:"dev.webox.builtin.podcasts",name:"播客",version:"1.1.3",requires:["html","audio"],allowHttp:true,
 cache:{list:300,detail:120,filters:3600},
 settings:{fields:[{key:"country",label:"默认地区",type:"text",default:"CN",maxLength:2,help:"两位地区代码，例如 CN、US 或 SG"},{key:"feed",label:"RSS 订阅地址",type:"url",required:false,default:""}]},
 async filters(){return [{key:"genre",label:"分类",type:"select",default:"all",options:podcastGenres.concat([{label:"RSS 订阅",value:"feed",home:false}])}]},
 async list(ctx,req){if(req.cursor)return {items:[],nextCursor:null};if(req.filters.genre==='feed'){
  if(!ctx.settings.feed)ctx.fail('CONFIG_REQUIRED','请先在播客设置中填写 RSS 地址',{fields:['feed']});
  const f=await podcastFeed(ctx,ctx.settings.feed);return {items:[{id:'rss:'+ctx.settings.feed,title:f.title,kind:'series',poster:f.poster,subtitle:f.author}],nextCursor:null};
 }return podcastCharts(ctx,req.filters.genre||'all',req.surface==='home'?10:200)},
 async search(ctx,req){if(req.cursor)return {items:[],nextCursor:null};return podcastSearch(ctx,req.query)},
 async detail(ctx,req){const f=await podcastFeed(ctx,await podcastFeedUrl(ctx,req.id));return {id:req.id,title:f.title,kind:'series',poster:f.poster,summary:f.summary,groups:[{id:'episodes',name:'单集',episodes:f.items.map(e=>({id:e.id,name:e.title,...(ctx.capabilities?.episodeMetadata?{subtitle:e.subtitle,poster:e.poster}:{} )}))}]}},
 async play(ctx,req){const f=await podcastFeed(ctx,await podcastFeedUrl(ctx,req.contentId),req.episodeId);const item=f.items.find(x=>x.id===req.episodeId);if(!item)ctx.fail('NOT_FOUND','RSS 已不包含这期节目，请重新读取节目');return {sources:[{id:'rss',name:'节目音频',url:item.url,mime:item.mime,downloadable:true,...(ctx.capabilities?.episodeMetadata?{summary:item.summary||f.summary}:{})}]}}
});
async function podcastRequest(ctx,url){const r=await ctx.http.get(url,{responseType:'text',timeoutMs:15000});if(r.status<200||r.status>=300)ctx.fail('NETWORK','播客接口返回 HTTP '+r.status,{httpStatus:r.status});return r.data}
async function podcastSearch(ctx,query){const q=String(query||'').trim();if(!q)return {items:[],nextCursor:null};const country=String(ctx.settings.country||'CN').toUpperCase();if(!/^[A-Z]{2}$/.test(country))ctx.fail('CONFIG_REQUIRED','搜索地区请填写两位代码，例如 CN、US 或 SG',{fields:['country']});
 const data=JSON.parse(await podcastRequest(ctx,'https://itunes.apple.com/search?media=podcast&entity=podcast&limit=40&country='+country+'&term='+encodeURIComponent(q)));
 if(!Array.isArray(data.results))ctx.fail('INVALID_RESPONSE','播客搜索没有返回列表');
 const seen=new Set();return {items:data.results.filter(x=>x.collectionId&&x.collectionName&&!seen.has(String(x.collectionId))&&seen.add(String(x.collectionId))).map(x=>({id:'apple:'+x.collectionId,title:x.collectionName,kind:'series',poster:x.artworkUrl600||x.artworkUrl100||'',subtitle:x.artistName||''})),nextCursor:null};
}
async function podcastFeedUrl(ctx,id){if(id.startsWith('rss:'))return id.slice(4);if(!/^apple:[0-9]+$/.test(id))ctx.fail('NOT_FOUND','播客身份无效');
 const r=JSON.parse(await podcastRequest(ctx,'https://itunes.apple.com/lookup?entity=podcast&id='+id.slice(6)));const p=(r.results||[]).find(x=>String(x.collectionId)===id.slice(6)&&x.feedUrl);if(!p)ctx.fail('NOT_FOUND','节目未提供可访问的 RSS');return p.feedUrl;
}
function podcastId(value){let a=2166136261,b=5381;for(let i=0;i<value.length;i++){a=Math.imul(a^value.charCodeAt(i),16777619);b=Math.imul(b,33)^value.charCodeAt(i)}return (a>>>0).toString(16)+'-'+(b>>>0).toString(16)}
async function podcastFeed(ctx,url,notesFor=null){const raw=await podcastRequest(ctx,url);if(/<!DOCTYPE|<!ENTITY/i.test(raw))ctx.fail('INVALID_RESPONSE','RSS 含不支持的实体声明');
 const clean=x=>podcastText(ctx,x);let feed=null;const items=[],seen=new Set();
 for(const part of podcastRssParts(raw)){
  if(part.header!=null){const $=ctx.html.load(part.header,{xmlMode:true}),ch=$('rss > channel').first();if(!ch.length)ctx.fail('INVALID_RESPONSE','地址没有返回 RSS 2.0 播客');const title=clean(ch.children('title').first().text());if(!title)ctx.fail('INVALID_RESPONSE','RSS 缺少节目名称');
   const poster=ch.children().filter((_,e)=>e.tagName==='itunes:image').first().attr('href')||ch.children('image').children('url').text()||'';
   feed={title:title.slice(0,240),poster:podcastPoster(ctx,poster,url),author:clean(ch.children().filter((_,e)=>e.tagName==='itunes:author').text()||ch.children('author').text()),summary:clean(ch.children('description').text()).slice(0,65000),items};continue;
  }
  const compact=podcastItemMetadata(part.item),$=ctx.html.load(compact,{xmlMode:true}),e=$('item').first(),en=e.children('enclosure').first(),link=en.attr('url'),name=clean(e.children('title').text());if(!link||!/^https?:\/\//i.test(link)||!name)continue;
  const guid=e.children('guid').first().text().trim()||e.children('link').first().text().trim()||link,id=podcastId(guid);if(seen.has(id))continue;seen.add(id);
  if(notesFor!=null&&id!==notesFor)continue;
  const image=e.children().filter((_,node)=>node.tagName==='itunes:image'||node.tagName==='media:thumbnail').first();let notes='';
  if(id===notesFor){const body=podcastItemNotes(part.item);notes=clean(ctx.html.load('<notes>'+body+'</notes>',{xmlMode:true}).text()).slice(0,65000);}
  items.push({id,title:name.slice(0,240),url:link,mime:en.attr('type')||'audio/mpeg',subtitle:podcastEpisodeMeta(e.children('pubDate').first().text(),e.children().filter((_,node)=>node.tagName==='itunes:duration').first().text()),poster:podcastPoster(ctx,image.attr('href')||image.attr('url')||feed?.poster||'',url),summary:notes});
  if(notesFor!=null||items.length>=1000)break;
 }
 if(!feed)ctx.fail('INVALID_RESPONSE','地址没有返回 RSS 2.0 播客');return feed;
}
// Scan XML boundaries without making the complete (often multi-megabyte) RSS into a DOM.
function* podcastXmlTags(raw){let i=0;while((i=raw.indexOf('<',i))>=0){const start=i;
 if(raw.startsWith('<!--',i)){i=raw.indexOf('-->',i+4);if(i<0)throw new Error('RSS 注释未结束');i+=3;continue;}
 if(raw.startsWith('<![CDATA[',i)){i=raw.indexOf(']]>',i+9);if(i<0)throw new Error('RSS CDATA 未结束');i+=3;continue;}
 if(raw.startsWith('<?',i)){i=raw.indexOf('?>',i+2);if(i<0)throw new Error('RSS 声明未结束');i+=2;continue;}
 let quote='',end=i+1;for(;end<raw.length;end++){const c=raw[end];if(quote){if(c===quote)quote='';}else if(c==='"'||c==="'")quote=c;else if(c==='>')break;}
 if(end===raw.length)throw new Error('RSS 标签未结束');const token=raw.slice(i+1,end),match=/^\s*(\/?)\s*([\w:.-]+)/.exec(token);i=end+1;
 if(match)yield {start,end:i,name:match[2],close:!!match[1],single:/\/\s*$/.test(token)};
}}
function* podcastRssParts(raw){const stack=[],ranges=[],header=[];let channel=-1,item=-1,from=0,found=false;
 for(const t of podcastXmlTags(raw)){
  if(!t.close){
   if(t.name==='channel'&&stack.length===1&&stack[0]==='rss'){channel=stack.length+1;found=true;}
   if(channel>0&&stack.length===channel&&t.name==='item'){
    if(!t.single)item=t.start;else{header.push(raw.slice(from,t.start));from=t.end;}
   }
   if(!t.single){stack.push(t.name);if(stack.length>128)throw new Error('RSS 嵌套过深');}
  }else{
   if(stack.pop()!==t.name)throw new Error('RSS 标签不匹配');
   if(t.name==='item'&&item>=0&&stack.length===channel){header.push(raw.slice(from,item));from=t.end;ranges.push([item,t.end]);if(ranges.length>100000)throw new Error('RSS 单集数量过多');item=-1;}
   if(t.name==='channel'&&stack.length===channel-1)channel=-1;
  }
 }
 if(stack.length)throw new Error('RSS 内容不完整');
 if(!found)return;header.push(raw.slice(from));yield {header:header.join('')};
 for(const [start,end] of ranges)yield {item:raw.slice(start,end)};
}
function podcastItemMetadata(raw){let depth=0,skip=-1,skipDepth=0,out='',from=0;
 for(const t of podcastXmlTags(raw)){
  if(!t.close){if(depth===1&&['description','content:encoded','itunes:summary'].includes(t.name)&&skip<0){skip=t.start;skipDepth=depth;if(t.single){out+=raw.slice(from,skip);from=t.end;skip=-1;}}
   if(!t.single)depth++;
  }else{depth--;if(skip>=0&&depth===skipDepth){out+=raw.slice(from,skip);from=t.end;skip=-1;}}
 }return out+raw.slice(from);
}
function podcastItemNotes(raw){let depth=0,start=-1,name='',fallback='';
 for(const t of podcastXmlTags(raw)){
  if(!t.close){if(depth===1&&['description','content:encoded','itunes:summary'].includes(t.name)&&!t.single){start=t.end;name=t.name;}if(!t.single)depth++;}
  else{depth--;if(depth===1&&start>=0){let text=raw.slice(start,t.start);const cdata=/^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/.exec(text);text=cdata?'<![CDATA['+cdata[1].slice(0,130000)+']]>':text.slice(0,130000);if(name!=='description'&&text.trim())return text;if(!fallback)fallback=text;start=-1;}}
 }return fallback;
}

function podcastPoster(ctx,value,base){if(!value)return '';try{const url=ctx.url.resolve(value,base);return /^https?:\/\//i.test(url)?url:''}catch(e){return ''}}

async function podcastCharts(ctx,genre,limit=200){const country=String(ctx.settings.country||'CN').toLowerCase();if(!/^[a-z]{2}$/.test(country))ctx.fail('CONFIG_REQUIRED','搜索地区请填写两位代码',{fields:['country']});let items;
 if(genre&&genre!=='all'||limit>100){if(genre&&genre!=='all'&&!podcastGenres.some(x=>x.value===genre&&x.value!=='all'))ctx.fail('INVALID_RESPONSE','未知的节目分类');const j=JSON.parse(await podcastRequest(ctx,'https://itunes.apple.com/'+country+'/rss/toppodcasts/limit='+limit+(genre&&genre!=='all'?'/genre='+genre:'')+'/json'));const entries=j.feed?.entry;if(entries!=null&&!Array.isArray(entries))ctx.fail('INVALID_RESPONSE','分类榜单未返回节目');if(!j.feed)ctx.fail('INVALID_RESPONSE','分类榜单未返回节目');items=(entries||[]).map(x=>({id:'apple:'+x.id?.attributes?.['im:id'],title:x['im:name']?.label,kind:'series',poster:x['im:image']?.at(-1)?.label||'',subtitle:x['im:artist']?.label||''}));}
 else {const j=JSON.parse(await podcastRequest(ctx,'https://rss.marketingtools.apple.com/api/v2/'+country+'/podcasts/top/'+limit+'/podcasts.json'));if(!Array.isArray(j.feed?.results))ctx.fail('INVALID_RESPONSE','热门榜单未返回节目');items=j.feed.results.map(x=>({id:'apple:'+x.id,title:x.name,kind:'series',poster:x.artworkUrl100||'',subtitle:x.artistName||''}));}
 const seen=new Set();return {items:items.filter(x=>/^apple:[0-9]+$/.test(x.id)&&x.title&&!seen.has(x.id)&&seen.add(x.id)),nextCursor:null};}

const podcastGenres=[{"label": "热门榜单", "value": "all", "home": false}, {"label": "艺术", "value": "1301"}, {"label": "喜剧", "value": "1303"}, {"label": "教育", "value": "1304"}, {"label": "儿童与家庭", "value": "1305"}, {"label": "电视与电影", "value": "1309"}, {"label": "音乐", "value": "1310"}, {"label": "宗教与信仰", "value": "1314"}, {"label": "技术", "value": "1318"}, {"label": "社会与文化", "value": "1324"}, {"label": "小说", "value": "1483"}, {"label": "历史", "value": "1487"}, {"label": "犯罪", "value": "1488"}, {"label": "新闻", "value": "1489"}, {"label": "休闲", "value": "1502"}, {"label": "政府", "value": "1511"}, {"label": "健康与健身", "value": "1512"}, {"label": "科学", "value": "1533"}, {"label": "运动", "value": "1545"}, {"label": "商务", "value": "1321"}];

function podcastText(ctx,value){return ctx.html.load(String(value||'').replace(/<br\s*\/?\s*>/gi,'\n').replace(/<\/(?:p|div|li|h[1-6])\s*>/gi,'\n')).text().replace(/\n[ \t]+/g,'\n').replace(/\n{3,}/g,'\n\n').trim()}
function podcastEpisodeMeta(rawDate,rawDuration){
 let date='';const stamp=Date.parse(String(rawDate||''));if(Number.isFinite(stamp))date=new Date(stamp+8*3600000).toISOString().slice(0,10);
 const raw=String(rawDuration||'').trim();let seconds=NaN;
 if(/^\d+(?:\.\d+)?$/.test(raw))seconds=Math.floor(Number(raw));
 else if(/^\d{1,3}:\d{2}(?::\d{2})?$/.test(raw))seconds=raw.split(':').reduce((total,value)=>total*60+Number(value),0);
 let duration='';if(Number.isFinite(seconds)&&seconds>=0&&seconds<=604800){
  const h=Math.floor(seconds/3600),m=Math.floor(seconds/60)%60,s=seconds%60;
  duration=(h?h+':':'')+String(h?m:Math.floor(seconds/60)).padStart(2,'0')+':'+String(s).padStart(2,'0');
 }
 return [date,duration].filter(Boolean).join(' · ');
}
