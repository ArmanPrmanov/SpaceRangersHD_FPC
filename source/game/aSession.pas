{$EXCESSPRECISION OFF}
unit aSession;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - Game state of the running session that is not part of the galaxy: the
// load context, the script runtime's stacks and the turn thread. These were globals in
// Globals, GlobalsV and GR_Main; the fields keep their names. State of the human at this
// machine is in aHuman instead. tools/layers_globals.txt classifies the other globals the
// simulation uses.
interface
uses
  Classes,
  EC_BlockPar,
  EC_Expression,
  ThreadCalc,
  aItem;
type
  TSessionState = record
    // The version of the save being loaded.
    LoadedSaveVersion: Integer;
    LoadedSaveModSet: WideString;
    LastLoadedPlayerName: WideString;
    EditableSaveBlock: TBlockParEC;
    ApplyEditableSaveOnLoad: Boolean;
    GameEndReason: Integer;
    ForcedPlanetQuestId: Integer;
    UselessItemRemainsCount: Integer;
    // Whether the player star's day has been prepared ahead of the turn.
    PlayerStarDayPrepared: Boolean;
    TurnCalculationThread: TThreadCalc;
    // The script runtime.
    GlobalScriptVariables: TVarArrayEC;
    SharedScriptVariables: TVarArrayEC;
    ScriptTemplates: TList;
    ScriptTemplateStartRequested: Boolean;
    ScriptDialogIndex: Integer;
    ScriptUseItem: TItem;
    ScriptActionTypeStack: TList;
    ScriptActionShipStack: TList;
    ScriptActionObject1Stack: TList;
    ScriptActionObject2Stack: TList;
    ScriptActionParamStack: TList;
    ScriptItemContextStack: TList;
    ScriptItemInfoContextStack: TList;
    // Events by which the turn thread hands a conversation or a script's UI request to
    // the UI thread and waits for it.
    TalkRequestEvent: Cardinal;
    TalkCompletedEvent: Cardinal;
    ScriptUiRequestEvent: Cardinal;
    ScriptUiAbortEvent: Cardinal;
  end;
var
  Session: TSessionState;
implementation
initialization
  Session.ForcedPlanetQuestId := -1;
  Session.ScriptDialogIndex := -1;
end.
