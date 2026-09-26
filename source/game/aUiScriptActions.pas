{$EXCESSPRECISION OFF}
unit aUiScriptActions;
{$R-}
{$Q-}
{$B-}

// CHANGE: ENHANCEMENT - Script code the UI runs, and the script requests it dispatches, as
// commands (docs/commands.md).
// - UI code (ExecuteGameplayUiCode): the interface's OnKey, OnPressCode and mouse code blocks.
//   Each run is one command. The command carries the code's text and the keyboard state; the
//   UI runs the code it compiled for the block, and a replay compiles the text once.
// - Script requests queued by the simulation and dispatched by the UI
//   (DispatchPendingScriptRequests): the resuming script's request moving to the front of
//   its queue, a planetary battle's or video's outcome returning to its script, and the
//   script's takeoff and end-turn requests. What the UI shows in between stays in the UI.
// - Item action code run by the star map, the scanner and the uninhabited planet: the item's
//   info code on hover, and the custom selection's code on the star map.
//
// With no player (the main menu, a quest run from it) there is no one to act, and the code
// runs directly, unrecorded.
interface
uses
  aCommands,
  aScript,
  aItem,
  aShip;
const
  // Command kinds 650-699 (see TCommandKind).
  ckRunUiCode = 650;
  ckMoveResumingScriptRequest = 651;
  ckFinishQueuedPlanetaryBattle = 652;
  ckFinishQueuedVideo = 653;
  ckOrderScriptTakeoff = 654;
  ckClearScriptEndTurn = 655;
  ckItemInfoActionCode = 656;
  ckCustomSelectionAction = 657;

// Runs Entry's UI code with the key that ran it (0 for none) and the modifier keys held.
procedure RunUiCode(Entry: TScriptGICacheUnit; VirtualKey, KeyModifiers: Cardinal);
// Moves the resuming script's request to the front of its queue.
procedure MoveResumingScriptRequestToFront;
// The script that queued the planetary battle or video runs with the outcome.
procedure FinishQueuedPlanetaryBattle(Status: Integer);
procedure FinishQueuedVideo(Status: Integer);
// A script asked for takeoff: the request is taken, and the player ordered to take off when
// landed or docked. Returns whether the order was given.
function OrderScriptTakeoff: Boolean;
// Takes a script's end-turn request.
procedure ClearScriptEndTurn;
// Runs Item's script and config action code, each with Param 0, as the info panels do when
// they show the item.
procedure RunItemInfoActionCode(
    Item: TItem;
    ActionType: Byte;
    Ship: TShip;
    Object1: TObject;
    Object2: TObject
);
// The star map's custom selection acting on Target: the selecting item's action code, or with
// no item, the custom ship info named InfoName. Returns the action's result.
function RunCustomSelectionAction(
    ActionType: Byte;
    Item: TItem;
    const InfoName: WideString;
    Target: TObject
): PtrInt;
implementation
uses
  Contnrs,
  aGalaxyStruct,
  aHuman,
  aPlayer;

// Runs the command, or with no player to act, the executor directly.
procedure SubmitOrRun(const Command: TPlayerCommand; Executor: TCommandExecutor);
begin
  if GetPlayer = nil then
    Executor(Command)
  else
    SubmitCommand(Command);
end;

var
  // The entry the UI compiled for the code it runs; a replay has none.
  PendingUiCode: TScriptGICacheUnit;
  // The replay's entries, one per code text.
  ReplayUiCode: TObjectList;
  ScriptTakeoffOrdered: Boolean;
  CustomSelectionResult: PtrInt;

function UiCodeForText(const Text: WideString): TScriptGICacheUnit;
var
  I: Integer;
begin
  if ReplayUiCode = nil then
    ReplayUiCode := TObjectList.Create;
  for I := 0 to ReplayUiCode.Count - 1 do
  begin
    Result := TScriptGICacheUnit(ReplayUiCode[I]);
    if Result.SourceText = Text then
      Exit;
  end;
  Result := TScriptGICacheUnit.Create;
  Result.Initialize(nil, Text);
  ReplayUiCode.Add(Result);
end;

// Ints: the key, the modifier keys. Text: the code.
procedure ExecuteRunUiCode(const Command: TPlayerCommand);
var
  Entry: TScriptGICacheUnit;
begin
  Entry := PendingUiCode;
  PendingUiCode := nil;
  if (Entry = nil) or (Entry.SourceText <> Command.Text) then
    Entry := UiCodeForText(Command.Text);
  RunGameplayUiCodeEntry(Entry, Cardinal(IntArg(Command, 0)), Cardinal(IntArg(Command, 1)));
end;

procedure RunUiCode(Entry: TScriptGICacheUnit; VirtualKey, KeyModifiers: Cardinal);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckRunUiCode);
  AddInt(Command, Integer(VirtualKey));
  AddInt(Command, Integer(KeyModifiers));
  Command.Text := Entry.SourceText;
  PendingUiCode := Entry;
  try
    SubmitOrRun(Command, @ExecuteRunUiCode);
  finally
    PendingUiCode := nil;
  end;
end;

// Moved from TryDispatchResumingScriptRequest.
procedure ExecuteMoveResumingScriptRequest(const Command: TPlayerCommand);
var
  Queue, Index: Integer;
begin
  Queue := FindResumingScriptRequest(Index);
  if Index > 0 then
    MoveScriptRequestToFront(Queue, Index);
end;

procedure MoveResumingScriptRequestToFront;
begin
  SubmitOrRun(NewCommand(ckMoveResumingScriptRequest), @ExecuteMoveResumingScriptRequest);
end;

// Moved from TryRunQueuedPlanetaryBattle.
procedure ExecuteFinishQueuedPlanetaryBattle(const Command: TPlayerCommand);
begin
  CompleteQueuedPlanetaryBattle(IntArg(Command, 0));
end;

procedure FinishQueuedPlanetaryBattle(Status: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckFinishQueuedPlanetaryBattle);
  AddInt(Command, Status);
  SubmitOrRun(Command, @ExecuteFinishQueuedPlanetaryBattle);
end;

// Moved from TryShowQueuedVideo and TfRuinsTalk.StopScriptVideo.
procedure ExecuteFinishQueuedVideo(const Command: TPlayerCommand);
begin
  CompleteQueuedVideo(IntArg(Command, 0));
end;

procedure FinishQueuedVideo(Status: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckFinishQueuedVideo);
  AddInt(Command, Status);
  SubmitOrRun(Command, @ExecuteFinishQueuedVideo);
end;

// Moved from TryDispatchScriptTakeoff.
procedure ExecuteOrderScriptTakeoff(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  ScriptTakeoffRequested := False;
  ScriptTakeoffOrdered := (P.CurrentPlanet <> nil) or (P.DockedTo <> nil);
  if ScriptTakeoffOrdered then
    P.OrderTakeoff;
end;

function OrderScriptTakeoff: Boolean;
begin
  SubmitCommand(NewCommand(ckOrderScriptTakeoff));
  Result := ScriptTakeoffOrdered;
end;

// Moved from TryDispatchScriptTakeoff and TryDispatchScriptEndTurn.
procedure ExecuteClearScriptEndTurn(const Command: TPlayerCommand);
begin
  ScriptEndTurnRequested := False;
end;

procedure ClearScriptEndTurn;
begin
  SubmitOrRun(NewCommand(ckClearScriptEndTurn), @ExecuteClearScriptEndTurn);
end;

// Refs: the item, the ship, the two objects. Ints: the action.
// Moved from TfStarMap.ShowObjectInfo and ShowItemInfo, TfScaner's item hover and
// TfPlanetNO's item hover.
procedure ExecuteItemInfoActionCode(const Command: TPlayerCommand);
var
  Item: TItem;
begin
  Item := RefObject(Command, 0) as TItem;
  if Item.ScriptItem <> nil then
    TScriptItem(Item.ScriptItem)
        .RunActionCode(
            IntArg(Command, 0),
            RefObject(Command, 1) as TShip,
            RefObject(Command, 2),
            RefObject(Command, 3),
            0
        );
  if Item is TEquipmentWithActCode then
    RunItemConfigActionCode(
        Item,
        IntArg(Command, 0),
        RefObject(Command, 1) as TShip,
        RefObject(Command, 2),
        RefObject(Command, 3),
        0
    );
end;

procedure RunItemInfoActionCode(
    Item: TItem;
    ActionType: Byte;
    Ship: TShip;
    Object1: TObject;
    Object2: TObject
);
var
  Command: TPlayerCommand;
begin
  if not CanNameObject(Object1) or not CanNameObject(Object2) then
  begin
    if Item.ScriptItem <> nil then
      TScriptItem(Item.ScriptItem).RunActionCode(ActionType, Ship, Object1, Object2, 0);
    if Item is TEquipmentWithActCode then
      RunItemConfigActionCode(Item, ActionType, Ship, Object1, Object2, 0);
    Exit;
  end;
  Command := NewCommand(ckItemInfoActionCode);
  AddRef(Command, Item);
  AddRef(Command, Ship);
  AddRef(Command, Object1);
  AddRef(Command, Object2);
  AddInt(Command, ActionType);
  SubmitOrRun(Command, @ExecuteItemInfoActionCode);
end;

// The custom selection's action, the part both callers share.
function CustomSelectionAction(
    P: TPlayer;
    ActionType: Byte;
    Item: TItem;
    const InfoName: WideString;
    Target: TObject
): PtrInt;
var
  Index: Integer;
  Info: PCustomShipInfo;
  ActionResult: PtrInt;
begin
  ActionResult := 0;
  if Item <> nil then
  begin
    if Item.ScriptItem <> nil then
      ActionResult :=
          TScriptItem(Item.ScriptItem)
              .RunActionCode(ActionType, P, Target, nil, ActionResult);
    if Item is TEquipmentWithActCode then
      ActionResult :=
          RunItemConfigActionCode(Item, ActionType, P, Target, nil, ActionResult);
  end
  else
  begin
    for Index := 0 to P.CustomShipInfos.Count - 1 do
    begin
      Info := P.CustomShipInfos[Index];
      if not Info.DeleteQueued and (Info.TypeName = InfoName) then
      begin
        ActionResult :=
            RunCustomShipInfoActionCode(Info, ActionType, P, Target, nil, ActionResult);
        Break;
      end;
    end;
  end;
  Result := ActionResult;
end;

// Refs: the item, the target. Ints: the action. Text: the custom ship info's name.
// Moved from TfStarMap's custom selection click and hover.
procedure ExecuteCustomSelectionAction(const Command: TPlayerCommand);
begin
  CustomSelectionResult :=
      CustomSelectionAction(
          Actor(Command),
          IntArg(Command, 0),
          RefObject(Command, 0) as TItem,
          Command.Text,
          RefObject(Command, 1)
      );
end;

function RunCustomSelectionAction(
    ActionType: Byte;
    Item: TItem;
    const InfoName: WideString;
    Target: TObject
): PtrInt;
var
  Command: TPlayerCommand;
begin
  if not CanNameObject(Target) then
    Exit(CustomSelectionAction(GetPlayer, ActionType, Item, InfoName, Target));
  Command := NewCommand(ckCustomSelectionAction);
  AddRef(Command, Item);
  AddRef(Command, Target);
  AddInt(Command, ActionType);
  Command.Text := InfoName;
  SubmitCommand(Command);
  Result := CustomSelectionResult;
end;

initialization
  RegisterCommand(ckRunUiCode, 'RunUiCode', @ExecuteRunUiCode);
  RegisterCommand(
      ckMoveResumingScriptRequest,
      'MoveResumingScriptRequest',
      @ExecuteMoveResumingScriptRequest
  );
  RegisterCommand(
      ckFinishQueuedPlanetaryBattle,
      'FinishQueuedPlanetaryBattle',
      @ExecuteFinishQueuedPlanetaryBattle
  );
  RegisterCommand(ckFinishQueuedVideo, 'FinishQueuedVideo', @ExecuteFinishQueuedVideo);
  RegisterCommand(ckOrderScriptTakeoff, 'OrderScriptTakeoff', @ExecuteOrderScriptTakeoff);
  RegisterCommand(ckClearScriptEndTurn, 'ClearScriptEndTurn', @ExecuteClearScriptEndTurn);
  RegisterCommand(ckItemInfoActionCode, 'ItemInfoActionCode', @ExecuteItemInfoActionCode);
  RegisterCommand(ckCustomSelectionAction, 'CustomSelectionAction', @ExecuteCustomSelectionAction);
finalization
  ReplayUiCode.Free;
end.
