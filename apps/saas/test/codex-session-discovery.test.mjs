import test from "node:test";
import assert from "node:assert/strict";
import {EventEmitter} from "node:events";
import {PassThrough,Writable} from "node:stream";
import {mkdtemp,mkdir,symlink,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {discoverStoredCodexSessions,safeCodexThreads,
  boundedCodexMessages} from "../../gateway/src/codex-session-discovery.mjs";

test("saved Codex discovery strictly isolates enrolled project, including symlinks",
  async()=>{
    const root=await mkdtemp(join(tmpdir(),"oagent-saved-"));
    const outside=await mkdtemp(join(tmpdir(),"oagent-elsewhere-"));
    try{
      await mkdir(join(root,"project"));
      await symlink(outside,join(root,"escape"),"dir");
      const list=[
        {id:"my-session-1234",cwd:join(root,"project"),
          preview:"My real workspace",updatedAt:1730831111,
          source:{kind:"vscode"}},
        {id:"other-session-1234",cwd:outside,preview:"Other project"},
        {id:"symlink-sess-1234",cwd:join(root,"escape"),preview:"Escape"},
        {id:"bad",cwd:root,preview:"Invalid id"},
      ];
      const result=await safeCodexThreads(list,root);
      assert.equal(result.length,1);
      assert.equal(result[0].sessionId,"my-session-1234");
      assert.equal(result[0].sourceKind,"vscode");
      assert.equal(result[0].title,"My real workspace");
    }finally{await rm(root,{recursive:true,force:true});
      await rm(outside,{recursive:true,force:true});}
  });
test("historical messages contain only bounded user and assistant text",
  ()=>{
    const messages=boundedCodexMessages({turns:[{items:[
      {type:"userMessage",content:[{type:"text",text:"Inspect repo"}]},
      {type:"reasoning",text:"PRIVATE REASONING"},
      {type:"agentMessage",text:"Done "+"x".repeat(3000)},
      {type:"commandExecution",command:"SECRET"}
    ]}]});
    assert.equal(messages.length,2);
    assert.deepEqual(messages.map(m=>m.role),["user","assistant"]);
    assert.equal(messages[1].text.length,600);
    assert.ok(!JSON.stringify(messages).includes("PRIVATE REASONING"));
  });
test("Codex app-server discovery only sends list/read RPC and never starts work",
  async()=>{
    const root=await mkdtemp(join(tmpdir(),"oagent-appsrv-"));
    const called=[];
    try{
      const spawnImpl=(command,args,options)=>{
        assert.equal(command,"codex");
        assert.deepEqual(args,["app-server"]);
        assert.equal(options.cwd,root);
        const process=new EventEmitter();
        process.stdout=new PassThrough();
        process.stderr=new PassThrough();
        let buffer="";
        process.stdin=new Writable({write(chunk,encoding,done){
          buffer+=chunk.toString();
          while(buffer.includes("\n")){
            const i=buffer.indexOf("\n"),line=buffer.slice(0,i);
            buffer=buffer.slice(i+1);
            const msg=JSON.parse(line);
            if(!msg.method)continue;
            called.push(msg.method);
            const result=msg.method==="initialize"?{}:
              msg.method==="thread/list"?{data:[{id:"saved-codex-1234",
                cwd:root,source:{kind:"cli"},name:"Existing Codex task",
                preview:"Fix native login",updatedAt:1730831111}]}:
              msg.method==="thread/read"?{thread:{turns:[{items:[
                {type:"userMessage",content:[{type:"text",
                  text:"Continue existing task"}]},
                {type:"agentMessage",text:"Files updated"}
              ]}]}}:{};
            queueMicrotask(()=>process.stdout.write(
              JSON.stringify({id:msg.id,result})+"\n"));
          }
          done();
        }});
        process.kill=()=>true;
        return process;
      };
      const sessions=await discoverStoredCodexSessions({
        root,isWindows:false,spawnImpl,timeoutMs:2000,env:{PATH:"/usr/bin"}});
      assert.deepEqual(called,["initialize","initialized","thread/list","thread/read"]);
      assert.equal(sessions.length,1);
      assert.equal(sessions[0].sessionId,"saved-codex-1234");
      assert.deepEqual(sessions[0].messages,[
        {role:"user",text:"Continue existing task"},
        {role:"assistant",text:"Files updated"},
      ]);
    }finally{await rm(root,{recursive:true,force:true});}
  });
