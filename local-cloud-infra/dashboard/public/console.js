const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const sample = {customer:'Demo customer',items:[{name:'Notebook',quantity:2,price:12.5},{name:'Pen',quantity:3,price:2}]};
let version = 0, poll;
const names = {home:'Console Home',stepfunctions:'Step Functions',lambda:'Lambda',s3:'Amazon S3',dynamo:'DynamoDB',sqs:'Amazon SQS',sns:'Amazon SNS',sample:'Sample application',health:'Service health'};
const subtitles = {home:'Manage your local cloud resources and applications.',stepfunctions:'Coordinate Lambda functions with visual workflows.',lambda:'Run code without provisioning or managing servers.',s3:'Store and retrieve objects in your local buckets.',dynamo:'Explore tables and application records.',sqs:'Inspect queues and send messages.',sns:'Publish messages to your topics.',sample:'Run an end-to-end order processing application.',health:'Live availability of your LocalStack services.'};
async function api(path, body) {
  const response = await fetch('/api/' + path, body === undefined ? {} : {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
  return result;
}
function error(err) { $('notice').textContent = err.message; $('notice').hidden = false; }
function card(title, body, action='') { return `<section class="card"><div class="cardhead"><h2>${title}</h2>${action}</div><div class="cardbody">${body}</div></section>`; }
function table(headers, rows, empty='No resources found') { return `<div class="tablewrap"><table><thead><tr>${headers.map(x=>`<th>${x}</th>`).join('')}</tr></thead><tbody>${rows.length ? rows.map(row=>`<tr>${row.map(cell=>`<td>${cell}</td>`).join('')}</tr>`).join('') : `<tr><td colspan="${headers.length}" class="empty">${empty}</td></tr>`}</tbody></table></div>`; }
function json(value) { try { return JSON.stringify(typeof value === 'string' ? JSON.parse(value) : value,null,2); } catch { return String(value); } }
function badge(status) { return `<span class="badge ${['SUCCEEDED','COMPLETED','ACTIVE','PROCESSED','AVAILABLE','RUNNING_SERVICE'].includes(status)?'good':['FAILED','TIMED_OUT','ABORTED'].includes(status)?'bad':status==='RUNNING'?'running':''}">${esc(status)}</span>`; }
function when(value) { return value ? esc(new Date(value).toLocaleString()) : '—'; }
function link(label, action, value) { return `<button class="link" data-action="${action}" data-value="${esc(value)}">${esc(label)}</button>`; }
function modal(title, body) { $('modalTitle').textContent=title; $('modalBody').innerHTML=body; if (!$('modal').open) $('modal').showModal(); }
function form(title, value, onSubmit, description='') {
  modal(title,`<p class="description">${esc(description)}</p><label for="payload">JSON input</label><textarea id="payload" spellcheck="false">${esc(json(value))}</textarea><div id="formError" class="bad" role="alert"></div><div class="actions"><button id="submitForm" class="primary">${title}</button></div>`);
  $('submitForm').onclick=async()=>{const button=$('submitForm');try{const input=JSON.parse($('payload').value);button.disabled=true;await onSubmit(input);}catch(err){if($('formError'))$('formError').textContent=err.message;else error(err);}finally{button.disabled=false;}};
}
async function render() {
  const current=++version;
  clearTimeout(poll);$('notice').hidden=true;
  const [page='home',resource]=location.hash.slice(1).split('/');
  if(!names[page]){location.hash='home';return;}
  $('title').textContent=names[page];$('subtitle').textContent=subtitles[page];$('breadcrumbs').textContent='Console Home'+(page==='home'?'':'  ›  '+names[page]);
  document.querySelectorAll('nav a').forEach(a=>a.classList.toggle('active',a.hash==='#'+page));
  $('content').innerHTML='<div class="loading">Loading resources…</div>';
  try {
    let html='';
    if(page==='home') {
      const [overview,machines]=await Promise.all([api('overview'),api('stepfunctions/machines')]);
      const services=[['stepfunctions','Step Functions','Visual workflows and execution history','⇄','#c925d1'],['lambda','Lambda','Functions and test invocations','λ','#ed7100'],['s3','Amazon S3','Buckets and object storage','▣','#3f8624'],['dynamo','DynamoDB','Tables and application records','▤','#2e73b8'],['sqs','Amazon SQS','Message queues','≋','#c925d1'],['sns','Amazon SNS','Topics and notifications','◉','#c925d1']];
      html=`<div class="grid">${card('Services',`<div class="servicegrid">${services.map(([p,n,d,i,c])=>`<a class="service" href="#${p}"><span class="icon" style="background:${c}">${i}</span><b>${n}</b><small>${d}</small></a>`).join('')}</div>`)}${card('Application',`<h3>Sample order processing</h3><p class="description">An order moves through validation, total calculation, and storage. Step Functions coordinates three Lambda tasks and writes completed orders to DynamoDB.</p><a href="#sample">Open sample application →</a><div class="flow"><div class="node">ValidateOrder<small>Lambda</small></div><div class="arrow">↓</div><div class="node">CalculateTotal<small>Lambda</small></div><div class="arrow">↓</div><div class="node">SaveOrder<small>Lambda → DynamoDB</small></div></div>`)}<div class="wide">${card('Resources in us-east-1',`<div class="stats">${[[overview.s3Buckets.length,'S3 buckets'],[overview.lambdaFunctions.length,'Lambda functions'],[machines.length,'State machines'],[overview.dynamoTables.length,'DynamoDB tables'],[overview.sqsQueues.length,'SQS queues']].map(([count,label])=>`<div><strong>${count}</strong><span>${label}</span></div>`).join('')}</div>`)}</div></div>`;
    } else if(page==='stepfunctions'||page==='sample') {
      const machines=await api('stepfunctions/machines');
      const selected=resource?machines.find(m=>m.name===decodeURIComponent(resource)):page==='sample'?machines.find(m=>m.name==='sample-order-processing'):null;
      if(selected) html=await machineView(selected,page==='sample');
      else html=card(`State machines (${machines.length})`,table(['Name','Type','Creation date'],machines.map(m=>[`<a href="#stepfunctions/${encodeURIComponent(m.name)}">${esc(m.name)}</a>`,esc(m.type),when(m.creationDate)]),page==='sample'?'Sample application is not deployed yet. See sample-app/README.md.':'No state machines deployed'));
    } else if(page==='lambda') {
      const functions=await api('lambda/functions');
      html=card(`Functions (${functions.length})`,table(['Function name','Runtime','Handler','Last modified','Actions'],functions.map(f=>[esc(f.FunctionName),esc(f.Runtime),esc(f.Handler),when(f.LastModified),link('Test','invoke',f.FunctionName)])));
    } else if(page==='s3') {
      const buckets=await api('s3/buckets');
      if(resource){const bucket=decodeURIComponent(resource);const objects=await api('s3/objects?bucket='+encodeURIComponent(bucket));html=card(esc(bucket),table(['Object key','Size','Last modified'],objects.map(o=>[esc(o.Key),esc(o.Size)+' bytes',when(o.LastModified)])),`<button id="upload">Upload</button><input type="file" id="file" hidden>`);}
      else html=card(`Buckets (${buckets.length})`,table(['Bucket name','Creation date'],buckets.map(b=>[`<a href="#s3/${encodeURIComponent(b.Name)}">${esc(b.Name)}</a>`,when(b.CreationDate)])));
    } else if(page==='dynamo') {
      const tables=await api('dynamodb/tables');
      if(resource){const name=decodeURIComponent(resource);const items=await api('dynamodb/items?table='+encodeURIComponent(name));html=card(esc(name)+` · Items (${items.length})`,table(['Partition key','Sort key','Status','Record'],items.map(item=>[esc(item.pk),esc(item.sk),badge(item.status),`<details><summary>View record</summary><pre>${esc(json(item))}</pre></details>`])));}
      else html=card(`Tables (${tables.length})`,table(['Table name','Status','Key schema'],tables.map(t=>[`<a href="#dynamo/${encodeURIComponent(t.name)}">${esc(t.name)}</a>`,badge(t.status),(t.keySchema||[]).map(k=>esc(k.AttributeName)+' ('+esc(k.KeyType)+')').join(', ')])));
    } else if(page==='sqs') {
      const queues=await api('sqs/queues');html=card(`Queues (${queues.length})`,table(['Name','Messages available','Messages in flight','Actions'],queues.map(q=>[esc(q.name),esc(q.messagesVisible),esc(q.messagesInFlight),link('Send message','send',q.url)])));
    } else if(page==='sns') {
      const topics=await api('sns/topics');html=card(`Topics (${topics.length})`,table(['Name','ARN','Actions'],topics.map(t=>[esc(t.name),esc(t.arn),link('Publish message','publish',t.arn)])));
    } else if(page==='health') {
      const status=await api('status');html=card('Service availability',table(['Service','Status'],Object.entries(status.services||{}).map(([name,state])=>[esc(name),badge(state.toUpperCase())])));
    }
    if(current!==version)return;
    $('content').innerHTML=html;
    if($('upload')){$('upload').onclick=()=>$('file').click();$('file').onchange=async()=>{try{const file=$('file').files[0];if(!file)return;const body=new FormData();body.append('bucket',decodeURIComponent(resource));body.append('file',file);const response=await fetch('/api/s3/upload',{method:'POST',body});if(!response.ok)throw new Error((await response.json()).error);await render();}catch(err){error(err);}};}
  }catch(err){if(current===version){$('content').innerHTML='<div class="empty">Unable to load resources. Use Refresh to retry.</div>';error(err);}}
}
async function machineView(machine,isSample) {
  const [detail,executions]=await Promise.all([api('stepfunctions/machine?arn='+encodeURIComponent(machine.stateMachineArn)),api('stepfunctions/executions?arn='+encodeURIComponent(machine.stateMachineArn))]);
  const definition=JSON.parse(detail.definition);
  const nodes=[];
  const seen=new Set();
  let next=definition.StartAt;
  while(next && !seen.has(next) && definition.States[next]) {
    seen.add(next);
    const state=definition.States[next];
    nodes.push([next,state]);
    next=state.Next;
  }
  const failures=[...new Set(nodes.flatMap(([,state])=>(state.Catch||[]).map(c=>c.Next)))];
  return `${isSample?'<div class="info">Submit an order and follow its execution through three Lambda functions. Completed orders appear in <a href="#dynamo/sample-orders">sample-orders</a>.</div>':''}${card(esc(machine.name),`<div class="summary"><div><label>Type</label>${esc(machine.type)}</div><div><label>Status</label>${badge(detail.status)}</div></div><small class="muted">${esc(machine.stateMachineArn)}</small>`,`<button class="primary" data-action="start" data-value="${esc(machine.stateMachineArn)}">Start execution</button>`)}<div class="split">${card('Workflow',`<div class="flow"><span class="badge">Start</span><div class="arrow">↓</div>${nodes.map(([name,state])=>`<div class="node">${esc(name)}<small>${state.Type==='Task'?'Lambda task':esc(state.Type)}</small></div><div class="arrow">↓</div>`).join('')}<span class="badge">End</span>${failures.length?'<p class="muted">On task error ↓</p>'+failures.map(name=>`<div class="node failed">${esc(name)}<small>Fail state</small></div>`).join(''):''}</div>`)}${card(`Executions (${executions.length})`,table(['Name','Status','Started','Finished'],executions.map(e=>[link(e.name,'execution',e.executionArn),badge(e.status),when(e.startDate),when(e.stopDate)])))}</div>${card('Definition',`<details><summary>Amazon States Language</summary><pre>${esc(json(definition))}</pre></details>`)}`;
}
async function executionView(arn) {
  clearTimeout(poll);
  const data=await api('stepfunctions/execution?arn='+encodeURIComponent(arn));
  const states=[];
  let active;
  for(const event of data.events){
    if(event.stateEnteredEventDetails){active={name:event.stateEnteredEventDetails.name,status:event.type==='FailStateEntered'?'failed':''};states.push(active);}
    if(active && /(?:Failed|TimedOut)$/.test(event.type))active.status='failed';
    if(active && event.stateExitedEventDetails && active.status!=='failed')active.status='complete';
  }
  modal('Execution: '+data.name,`<div class="summary"><div><label>Status</label>${badge(data.status)}</div><div><label>Started</label>${when(data.startDate)}</div><div><label>Finished</label>${when(data.stopDate)}</div></div><div class="flow">${states.map(state=>`<div class="node ${state.status}">${esc(state.name)}</div><div class="arrow">↓</div>`).join('')}</div><h3>Input</h3><pre>${esc(json(data.input))}</pre><h3 style="margin-top:20px">Output</h3><pre>${esc(json(data.output||{error:data.error,cause:data.cause}))}</pre><h3 style="margin-top:20px">Event history</h3>${table(['ID','Event','Time'],data.events.map(e=>[esc(e.id),`<details><summary>${esc(e.type)}</summary><pre>${esc(json(e))}</pre></details>`,when(e.timestamp)]))}${data.historyTruncated?'<p class="muted">Showing the first 1,000 events.</p>':''}`);
  if(data.status==='RUNNING')poll=setTimeout(()=>{if($('modal').open)executionView(arn).catch(error);},1500);
}
document.addEventListener('click',async event=>{
  const button=event.target.closest('[data-action]');if(!button)return;const value=button.dataset.value;
  try{
    if(button.dataset.action==='execution')await executionView(value);
    if(button.dataset.action==='start')form('Start execution',sample,async input=>{const execution=await api('stepfunctions/start',{stateMachineArn:value,input});await render();await executionView(execution.executionArn);},'Enter the order payload. Step Functions invokes the Lambda tasks in sequence.');
    if(button.dataset.action==='invoke')form('Test function',{},async payload=>{const result=await api('lambda/invoke',{functionName:value,payload});modal('Invocation result',`<pre>${esc(json(result))}</pre>`);},value);
    if(button.dataset.action==='send')form('Send message',{message:'Hello from the console'},async input=>{const result=await api('sqs/send',{queueUrl:value,messageBody:input});modal('Message sent',`<pre>${esc(json(result))}</pre>`);});
    if(button.dataset.action==='publish')form('Publish message',{message:'Hello from the console'},async input=>{const result=await api('sns/publish',{topicArn:value,message:input});modal('Message published',`<pre>${esc(json(result))}</pre>`);});
  }catch(err){error(err);}
});
$('refresh').onclick=render;
$('close').onclick=()=>{$('modal').close();clearTimeout(poll);render();};
$('modal').addEventListener('close',()=>clearTimeout(poll));
$('services').onclick=()=>{if(innerWidth<650){$('sidebar').style.display=$('sidebar').style.display==='flex'?'none':'flex';}else $('sidebar').classList.toggle('hidden');};
$('search').addEventListener('input',event=>{const query=event.target.value.toLowerCase();document.querySelectorAll('nav a').forEach(a=>a.hidden=!a.textContent.toLowerCase().includes(query));});
$('search').addEventListener('keydown',event=>{if(event.key==='Enter'){const found=Object.entries(names).find(([,name])=>name.toLowerCase().includes(event.target.value.toLowerCase()));if(found){location.hash=found[0];event.target.value='';document.querySelectorAll('nav a').forEach(a=>a.hidden=false);}}});
window.addEventListener('hashchange',()=>{$('modal').close();render();});
async function health(){try{const data=await api('status');$('connection').textContent=data.online?'● LocalStack connected':'● LocalStack offline';$('connection').style.color=data.online?'#037f0c':'#d13212';}catch{$('connection').textContent='● Connection unavailable';}}
health();setInterval(health,15000);render();
