{$EXCESSPRECISION OFF}
unit aDialogActions;

// CHANGE: ENHANCEMENT - Script dialogs as commands (docs/commands.md). The conversation,
// government and station screens run the same script dialog code; each call that runs a
// script is one command. The script is the one the dialog belongs to (CurrentScript), named
// by its index in Galaxy.Scripts. The script code adds the answers to the open screen, as
// before.
interface
uses
  aCommands;
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
implementation
uses
  SysUtils,
  aGalaxy,
  aSession,
  aScript,
  GR_Main;

// Selects the dialog's script for the executor.
procedure AddCurrentScript(var Command: TPlayerCommand);
begin
  if CurrentScript = nil then
    AddInt(Command, -1)
  else
    AddInt(Command, Galaxy.Scripts.IndexOf(CurrentScript));
end;

function CommandScript(const Command: TPlayerCommand): TScript;
var
  Index: Integer;
begin
  Index := IntArg(Command, 0);
  if Index < 0 then
    raise Exception.Create(CommandKindName(Command.Kind) + ' names no script');
  Result := TScript(Galaxy.Scripts[Index]);
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
  AddCurrentScript(Command);
  AddInt(Command, Value);
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
  RegisterCommand(ckScriptAnswer, 'ScriptAnswer', @ExecuteScriptAnswer);
  RegisterCommand(ckScriptAnswerOnly, 'ScriptAnswerOnly', @ExecuteScriptAnswerOnly);
  RegisterCommand(ckScriptCallDialog, 'ScriptCallDialog', @ExecuteScriptCallDialog);
  RegisterCommand(ckScriptCallDialogByName, 'ScriptCallDialogByName', @ExecuteScriptCallDialogByName);
  RegisterCommand(ckScriptCallDialogMessage, 'ScriptCallDialogMessage', @ExecuteScriptCallDialogMessage);
  RegisterCommand(ckScriptAuxiliaryCode, 'ScriptAuxiliaryCode', @ExecuteScriptsAuxiliaryCode);
end.
