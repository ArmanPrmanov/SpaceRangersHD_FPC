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
  aHuman,
  aItem;
type
  TSessionState = record
    // The humans in the game (aHuman). LocalHuman is one of them while its ranger exists.
    Humans: THumanList;
    // The version of the save being loaded.
    LoadedSaveVersion: Integer;
    LoadedSaveModSet: WideString;
    LastLoadedPlayerName: WideString;
    EditableSaveBlock: TBlockParEC;
    ApplyEditableSaveOnLoad: Boolean;
    GameEndReason: Integer;
    ForcedPlanetQuestId: Integer;
    // CHANGE: ENHANCEMENT - Session flags (ROADMAP.md, Phase 4, item 10, and Phase 6). They
    // are part of the saved session (aHumanSave) and change only through the SetSessionFlag
    // command (aPlayerActions), so every machine sees a change at the same point.
    // Text quests are not offered while this is set; multiplayer sets it.
    TextQuestsDisabled: Boolean;
    // Whether a human may attack another human. The host owns the switch.
    FriendlyFireEnabled: Boolean;
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
const
  // The flags SetSessionFlag takes. The values are part of the command log format.
  SessionFlagTextQuestsDisabled = 0;
  SessionFlagFriendlyFire = 1;
var
  Session: TSessionState;
// Puts the session flags back to their defaults, as for a new game.
procedure ResetSessionFlags;
// Whether every session flag has its default value.
function SessionFlagsAreDefault: Boolean;
// Sets one flag; an unknown Flag changes nothing.
procedure SetSessionFlag(Flag: Integer; Value: Boolean);
implementation

procedure ResetSessionFlags;
begin
  Session.TextQuestsDisabled := False;
  Session.FriendlyFireEnabled := True;
end;

function SessionFlagsAreDefault: Boolean;
begin
  Result := not Session.TextQuestsDisabled and Session.FriendlyFireEnabled;
end;

procedure SetSessionFlag(Flag: Integer; Value: Boolean);
begin
  case Flag of
    SessionFlagTextQuestsDisabled: Session.TextQuestsDisabled := Value;
    SessionFlagFriendlyFire: Session.FriendlyFireEnabled := Value;
  end;
end;

initialization
  Session.ForcedPlanetQuestId := -1;
  Session.ScriptDialogIndex := -1;
  ResetSessionFlags;
end.
