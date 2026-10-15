{$EXCESSPRECISION OFF}
unit aDialogActions;

// CHANGE: ENHANCEMENT - Script dialogs as commands (docs/commands.md). The conversation,
// government and station screens run the same script dialog code; each call that runs a
// script is one command. The script is the one the dialog belongs to (CurrentScript). The
// script code adds the answers to the open screen, as before.
//
// CHANGE: BUGFIX - A command names its script by its key (aScript.TScriptKey), and an injected
// answer or an override by its entry key (TDialogEntryKey), appended after the old arguments:
// the script's index in Galaxy.Scripts and the answer's index in ScriptDialogInjections,
// which each machine builds itself, so on a host a client's answer ran another script. A log
// from before carries only the indices and replays by them. A key that names nothing is
// refused (rrTargetGone) before anything changes (docs/commands.md, Changing a command's
// arguments).
interface
uses
  aCommands,
  aScript;
const
  // Command kinds 300-319 (see TCommandKind).
  ckScriptAnswer = 300;
  ckScriptAnswerOnly = 301;
  ckScriptCallDialog = 302;
  ckScriptCallDialogByName = 303;
  ckScriptCallDialogMessage = 304;
  ckScriptAuxiliaryCode = 305;
// Runs the answer's action, then the message it leads to (RunScriptAnswer in the screens).
procedure ScriptAnswer(Answer: Integer);
// Runs the answer's action only, as the exit, takeoff and restart answers do.
procedure ScriptAnswerOnly(Answer: Integer);
// Opens the current script's dialog (TScript.CallDialog), or the dialog named by a script
// variable (TScript.CallDialogByVariable).
procedure ScriptCallDialog(Index: Integer);
procedure ScriptCallDialogByName(const Name: WideString);
procedure ScriptCallDialogMessage(Index: Integer);
// Every script's auxiliary code, as the screens run it before building their choices.
procedure RunScriptsAuxiliaryCode;

// CHANGE: BUGFIX - Naming scripts and dialog entries in commands.
// The old argument: the script's index in Galaxy.Scripts, -1 for none.
procedure AddScriptIndex(var Command: TPlayerCommand; Script: TScript);
// Appends the script's key (three integers; a nil script has one too).
procedure AddScriptKey(var Command: TPlayerCommand; Script: TScript);
// The script the command names: by the key at KeyArg when the command has it, else by the
// index at IndexArg (a log from before). AllowNone: the command may name no script (nil).
// Raises ECommandRefused (rrTargetGone) when the script is not there.
function ScriptArgument(
    const Command: TPlayerCommand;
    IndexArg, KeyArg: Integer;
    AllowNone: Boolean
): TScript;
// Appends the key of an entry of ScriptDialogInjections or ScriptDialogOverrides (five
// integers).
procedure AddInjectionKey(var Command: TPlayerCommand; Injection: PScriptDialogInjection);
procedure AddOverrideKey(var Command: TPlayerCommand; Entry: PScriptDialogOverride);
// The injected answer the command names: by the key at KeyArg when the command has it, else
// by the index at IndexArg. Raises ECommandRefused (rrTargetGone) when it is not there.
function InjectionArgument(
    const Command: TPlayerCommand;
    IndexArg, KeyArg: Integer
): PScriptDialogInjection;
// The override the command names by the key at KeyArg, or, in a log from before, the one the
// screens select (SelectedDialogOverride). Raises ECommandRefused (rrTargetGone) when there is
// none (the list was read at [0] without a check) or its script has ended.
function OverrideArgument(const Command: TPlayerCommand; KeyArg: Integer): PScriptDialogOverride;
implementation
uses
  SysUtils,
  aGalaxy,
  aSession,
  GR_Main;

procedure AddScriptIndex(var Command: TPlayerCommand; Script: TScript);
begin
  if Script = nil then
    AddInt(Command, -1)
  else
    AddInt(Command, Galaxy.Scripts.IndexOf(Script));
end;

procedure AddScriptKey(var Command: TPlayerCommand; Script: TScript);
var
  Key: TScriptKey;
begin
  Key := ScriptKeyOf(Script);
  AddInt(Command, Key.HumanId);
  AddInt(Command, Key.NameHash);
  AddInt(Command, Key.Ordinal);
end;

procedure Refuse(const Command: TPlayerCommand; const Text: AnsiString);
begin
  raise ECommandRefused.CreateReason(rrTargetGone, CommandKindName(Command.Kind) + ' ' + Text);
end;

function ScriptArgument(
    const Command: TPlayerCommand;
    IndexArg, KeyArg: Integer;
    AllowNone: Boolean
): TScript;
var
  Key: TScriptKey;
  Index: Integer;
  Found: Boolean;
begin
  if Length(Command.Ints) >= KeyArg + 3 then
  begin
    Key.HumanId := IntArg(Command, KeyArg);
    Key.NameHash := IntArg(Command, KeyArg + 1);
    Key.Ordinal := IntArg(Command, KeyArg + 2);
    Result := FindScriptByKey(Key, Found);
    if not Found then
      Refuse(Command, 'names a script that is not there');
  end
  else
  begin
    Index := IntArg(Command, IndexArg);
    if Index >= Galaxy.Scripts.Count then
      Refuse(Command, 'names a script that is not there');
    if Index < 0 then
      Result := nil
    else
      Result := TScript(Galaxy.Scripts[Index]);
  end;
  if (Result = nil) and not AllowNone then
    Refuse(Command, 'names no script');
end;

procedure AddEntryKey(var Command: TPlayerCommand; const Key: TDialogEntryKey);
begin
  AddInt(Command, Key.Script.HumanId);
  AddInt(Command, Key.Script.NameHash);
  AddInt(Command, Key.Script.Ordinal);
  AddInt(Command, Key.Hash);
  AddInt(Command, Key.Ordinal);
end;

function EntryKeyArg(const Command: TPlayerCommand; KeyArg: Integer): TDialogEntryKey;
begin
  Result.Script.HumanId := IntArg(Command, KeyArg);
  Result.Script.NameHash := IntArg(Command, KeyArg + 1);
  Result.Script.Ordinal := IntArg(Command, KeyArg + 2);
  Result.Hash := IntArg(Command, KeyArg + 3);
  Result.Ordinal := IntArg(Command, KeyArg + 4);
end;

procedure AddInjectionKey(var Command: TPlayerCommand; Injection: PScriptDialogInjection);
begin
  AddEntryKey(Command, InjectionKeyOf(Injection));
end;

procedure AddOverrideKey(var Command: TPlayerCommand; Entry: PScriptDialogOverride);
begin
  AddEntryKey(Command, OverrideKeyOf(Entry));
end;

function InjectionArgument(
    const Command: TPlayerCommand;
    IndexArg, KeyArg: Integer
): PScriptDialogInjection;
var
  Index: Integer;
begin
  if Length(Command.Ints) >= KeyArg + 5 then
    Result := FindInjectionByKey(EntryKeyArg(Command, KeyArg))
  else
  begin
    Result := nil;
    Index := IntArg(Command, IndexArg);
    if (ScriptDialogInjections <> nil)
        and (Index >= 0)
        and (Index < ScriptDialogInjections.Count) then
      Result := PScriptDialogInjection(ScriptDialogInjections[Index]);
  end;
  if Result = nil then
    Refuse(Command, 'names a missing dialog injection');
end;

function OverrideArgument(const Command: TPlayerCommand; KeyArg: Integer): PScriptDialogOverride;
begin
  if Length(Command.Ints) >= KeyArg + 5 then
    Result := FindOverrideByKey(EntryKeyArg(Command, KeyArg))
  else
    Result := SelectedDialogOverride;
  if (Result = nil) or (Result.Script = nil) then
    Refuse(Command, 'names a missing dialog override');
end;

// Ints: the script's index, the value, then the script's key.
function CommandScript(const Command: TPlayerCommand): TScript;
begin
  Result := ScriptArgument(Command, 0, 2, False);
  CurrentScript := Result;
end;

procedure ExecuteScriptAnswer(const Command: TPlayerCommand);
var
  Script: TScript;
begin
  Script := CommandScript(Command);
  Session.ScriptDialogIndex := -1;
  Script.ExecuteDialogAnswer(IntArg(Command, 1));
  if Session.ScriptDialogIndex < 0 then
    RaiseWideMessage('I_Script');
  Script.CallDialogMessage(Session.ScriptDialogIndex);
end;

procedure SubmitScriptCommand(Kind: TCommandKind; Value: Integer; const Text: WideString);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(Kind);
  AddScriptIndex(Command, CurrentScript);
  AddInt(Command, Value);
  AddScriptKey(Command, CurrentScript);
  Command.Text := Text;
  SubmitCommand(Command);
end;

procedure ScriptAnswer(Answer: Integer);
begin
  SubmitScriptCommand(ckScriptAnswer, Answer, '');
end;

procedure ExecuteScriptAnswerOnly(const Command: TPlayerCommand);
begin
  CommandScript(Command).ExecuteDialogAnswer(IntArg(Command, 1));
end;

procedure ScriptAnswerOnly(Answer: Integer);
begin
  SubmitScriptCommand(ckScriptAnswerOnly, Answer, '');
end;

procedure ExecuteScriptCallDialog(const Command: TPlayerCommand);
begin
  CommandScript(Command).CallDialog(IntArg(Command, 1));
end;

procedure ScriptCallDialog(Index: Integer);
begin
  SubmitScriptCommand(ckScriptCallDialog, Index, '');
end;

procedure ExecuteScriptCallDialogByName(const Command: TPlayerCommand);
begin
  CommandScript(Command).CallDialogByVariable(Command.Text);
end;

procedure ScriptCallDialogByName(const Name: WideString);
begin
  SubmitScriptCommand(ckScriptCallDialogByName, 0, Name);
end;

procedure ExecuteScriptCallDialogMessage(const Command: TPlayerCommand);
begin
  CommandScript(Command).CallDialogMessage(IntArg(Command, 1));
end;

procedure ScriptCallDialogMessage(Index: Integer);
begin
  SubmitScriptCommand(ckScriptCallDialogMessage, Index, '');
end;

procedure ExecuteScriptsAuxiliaryCode(const Command: TPlayerCommand);
var
  I: Integer;
begin
  for I := 0 to Galaxy.Scripts.Count - 1 do
    TScript(Galaxy.Scripts[I]).RunAuxiliaryCode;
end;

procedure RunScriptsAuxiliaryCode;
begin
  SubmitCommand(NewCommand(ckScriptAuxiliaryCode));
end;

initialization
  EnterActorStateHook := @EnterHumanDialogState;
  LeaveActorStateHook := @LeaveHumanDialogState;
  RegisterCommand(ckScriptAnswer, 'ScriptAnswer', @ExecuteScriptAnswer);
  RegisterCommand(ckScriptAnswerOnly, 'ScriptAnswerOnly', @ExecuteScriptAnswerOnly);
  RegisterCommand(ckScriptCallDialog, 'ScriptCallDialog', @ExecuteScriptCallDialog);
  RegisterCommand(ckScriptCallDialogByName, 'ScriptCallDialogByName', @ExecuteScriptCallDialogByName);
  RegisterCommand(ckScriptCallDialogMessage, 'ScriptCallDialogMessage', @ExecuteScriptCallDialogMessage);
  RegisterCommand(ckScriptAuxiliaryCode, 'ScriptAuxiliaryCode', @ExecuteScriptsAuxiliaryCode);
end.
