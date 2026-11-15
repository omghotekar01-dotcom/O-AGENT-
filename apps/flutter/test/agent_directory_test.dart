import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/agent_directory.dart';

void main() {
  final timestamp=DateTime.utc(2026,11,15,10,0);
  final worker=<String,dynamic>{
    'id':'worker-1','name':'My laptop',
    'last_seen_at':timestamp.subtract(const Duration(seconds:25))
      .toIso8601String(),
    'revoked_at':null,
    'capabilities':['workspace_inventory','codex_cli_turn','claude_agent_turn'],
  };
  final savedCodex=<String,dynamic>{
    'deviceId':'worker-1','sessionId':'saved-codex-1234',
    'sourceKind':'codex_cli','title':'Existing project',
    'cwd':'C:\\trusted\\project',
    'syncedAt':timestamp.subtract(const Duration(seconds:10))
      .toIso8601String(),
  };
  final claude=<String,dynamic>{
    'deviceId':'worker-1','kind':'claude_agent_turn',
    'sessionId':'real-claude-sdk-thread','cwd':'C:\\trusted\\project',
  };
  final copilot=<String,dynamic>{
    'deviceId':'worker-1','kind':'copilot_sdk_turn',
    'sessionId':'real-copilot-sdk-thread','cwd':'C:\\trusted\\project',
  };

  List<AgentDirectoryEntry> catalog({
    bool signedIn=true,
    List<Map<String,dynamic>>? workers,
    List<Map<String,dynamic>>? codex,
    List<Map<String,dynamic>>? sdk,
  }) => buildAgentDirectory(
    signedIn:signedIn,
    devices:workers??[],
    codexSessions:codex??[],
    sdkSessions:sdk??[],
    now:timestamp,
  );

  test('the main directory includes every requested type and keeps routes honest',(){
    final list=catalog();
    expect(list.map((x)=>x.id).toList(),[
      'codex','claude_sdk','copilot_sdk','vscode','github','cursor',
      'chatgpt','claude_web','gemini',
    ]);
    expect(list.singleWhere((x)=>x.id=='github').route,
      AgentRoute.legacyWorkspace);
    expect(list.singleWhere((x)=>x.id=='cursor').route,
      AgentRoute.legacyWorkspace);
    final chatgpt=list.singleWhere((x)=>x.id=='chatgpt');
    expect(chatgpt.state,AgentState.externalOnly);
    expect(chatgpt.hasVerifiedSession,false);
    expect(chatgpt.route,AgentRoute.remoteDesktop);
    expect(chatgpt.summary,contains('shared'));
    expect(chatgpt.officialUrl,isNull);
  });

  test('verified live saved Codex and SDK sessions are counted, never fabricated',(){
    final list=catalog(
      workers:[worker],
      codex:[savedCodex],
      sdk:[claude,copilot],
    );
    final codex=list.singleWhere((x)=>x.id=='codex');
    final claudeSdk=list.singleWhere((x)=>x.id=='claude_sdk');
    final copilotSdk=list.singleWhere((x)=>x.id=='copilot_sdk');
    expect(codex.state,AgentState.sessionReady);
    expect(codex.sessionCount,1);
    expect(claudeSdk.state,AgentState.sessionReady);
    expect(claudeSdk.sessionCount,1);
    expect(copilotSdk.state,AgentState.offline,
      reason:'A saved SDK session does not grant a missing worker capability');
    expect(list.singleWhere((x)=>x.id=='vscode').state,
      AgentState.workerEnabled);
  });

  test('offline or revoked worker cannot advertise resumable sessions',(){
    final inactive={...worker,'last_seen_at':
      timestamp.subtract(const Duration(minutes:5)).toIso8601String()};
    for(final d in [inactive,{...worker,'revoked_at':'2026-11-15T09:00:00Z'}]){
      final list=catalog(workers:[d],codex:[savedCodex],sdk:[claude]);
      expect(list.singleWhere((x)=>x.id=='codex').state,AgentState.offline);
      expect(list.singleWhere((x)=>x.id=='claude_sdk').hasVerifiedSession,false);
      expect(list.singleWhere((x)=>x.id=='vscode').state,AgentState.needsSetup);
    }
  });

  test('unauthenticated catalog never leaks private worker or session counts',(){
    final list=catalog(
      signedIn:false,workers:[worker],codex:[savedCodex],sdk:[claude]);
    for(final id in ['codex','claude_sdk','copilot_sdk','vscode']){
      final entry=list.singleWhere((x)=>x.id==id);
      expect(entry.hasVerifiedSession,false);
      expect(entry.status,contains('Sign in'));
      expect(entry.sessionCount,0);
    }
    expect(list.singleWhere((x)=>x.id=='chatgpt').state,
      AgentState.externalOnly);
  });

  test('AI agent operation is preferred over workspace inventory diagnostics',(){
    expect(preferredAgentOperation([
      'workspace_inventory','codex_cli_turn']), 'codex_cli_turn');
    expect(preferredAgentOperation([
      'workspace_inventory','copilot_sdk_turn']), 'copilot_sdk_turn');
    expect(preferredAgentOperation([
      'workspace_inventory','claude_agent_turn']), 'claude_agent_turn');
    expect(preferredAgentOperation([
      'workspace_inventory','claude_agent_turn'],selected:'workspace_inventory'),
      'workspace_inventory');
    expect(preferredAgentOperation(['workspace_inventory']),
      'workspace_inventory');
    expect(preferredAgentOperation([]),isNull);
  });

  test('capable worker without verified session is enabled, not connected',(){
    final list=catalog(workers:[worker]);
    expect(list.singleWhere((x)=>x.id=='codex').state,
      AgentState.workerEnabled);
    expect(list.singleWhere((x)=>x.id=='codex').sessionCount,0);
    expect(list.singleWhere((x)=>x.id=='claude_sdk').status,
      contains('no verified active session'));
  });
  test('Codex sync older than five minutes must not be shown as resume-ready',(){
    final stale={...savedCodex,'syncedAt':
      timestamp.subtract(const Duration(minutes:6)).toIso8601String()};
    final list=catalog(workers:[worker],codex:[stale]);
    final entry=list.singleWhere((x)=>x.id=='codex');
    expect(entry.state,AgentState.workerEnabled);
    expect(entry.hasVerifiedSession,false);
    expect(entry.sessionCount,1);
  });

}
