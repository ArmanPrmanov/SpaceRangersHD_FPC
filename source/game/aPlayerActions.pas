{$EXCESSPRECISION OFF}
unit aPlayerActions;

// CHANGE: ENHANCEMENT - What a human does to the game, as commands (aCommands). The UI calls
// the procedures in the interface; each builds a command and submits it, and the executor
// below does what the UI used to do itself. The executors take the acting ranger from the
// command, never from the screen.
interface
uses
  Types,
  aShip;
type
  TSlotList = array of Integer;
procedure AddWeaponSlot(var Slots: TSlotList; Slot: Integer);

// The headless runner and the observer keep the player docked while turns pass.
procedure ParkPlayer;
// Removes the message bubbles that have run out.
procedure PruneMessages;
// Stops the ship and forgets a pending auto-battle target.
procedure OrderStop;
// Builds Ship's path the way the star map shows it; for a ship that follows another this
// also picks the point it heads for. Returns the days to land when the player's own ship
// lands on a planet, else -1.
function PrepareShipPath(Ship: TShip): Integer;
// Whether PrepareShipPath changes anything for Ship's order.
function ShipPathNeedsPreparing(Ship: TShip): Boolean;
// PrepareShipPath for the player's ship, whose path the next day uses.
procedure PreparePlayerPath;
// Rebuilds the player's path for the order it has.
procedure BuildPlayerPath;

const
  // OrderMoveTo flags.
  mfClearPending = 1;
  // Moves the end of the path back from its last nodes, as a click in empty space does.
  mfCorrectEnd = 2;
  // Gives the order without building the path.
  mfNoPath = 4;
procedure OrderMoveTo(const Destination: TPointF; Flags: Integer);
// Lands on a planet or docks with a ship; Offset is the landing point from its centre.
procedure OrderLandAt(Location: TObject; const Offset: TPointF);
procedure OrderJumpThroughHole(Hole: TObject; const Destination: TPointF);
// Follows Ship: mode 0 close, 1 at weapon range.
procedure OrderFollow(Ship: TShip; Mode: Integer);
// Stops, and fights Target (if any) when the day starts.
procedure OrderAutoBattle(Target: TShip);
// Aims the weapons in the given slots (0-4) at Target; nil clears them.
procedure SetWeaponTargets(Target: TObject; const Slots: array of Integer);
procedure SetInterceptorTarget(Target: TShip);
// Adds Item to the cargo hook's list, or removes it when it is there already.
procedure TogglePickupTarget(Item: TObject);
// Puts Item first in the cargo hook's list.
procedure PrioritizePickupTarget(Item: TObject);
procedure TogglePickupTargetsInRange(IgnoreRange: Boolean);
procedure SetPendingFollowTarget(Ship: TShip);
procedure SetAfterburner(Active: Boolean);
// The capital ship's bridge.
procedure EnterBridge(Mode: Integer);
procedure LeaveBridge;
procedure CancelInvalidTravelOrder;
procedure RefreshPlayerStarSteps;
// Runs Ship's script hook ActionType. Objects a command cannot name make it run directly,
// unrecorded; the command log then writes a checkpoint.
function RunScriptItemsAct(
    Ship: TShip;
    ActionType: Byte;
    Object1: TObject;
    Object2: TObject;
    Param: Integer
): PtrInt;
// Every script's turn code, as the jump into a black hole runs it.
procedure RunScriptTurns;
// The engine wears when the player lands on an uninhabited planet.
procedure ApplyLandingWear;

// The in-space day, before the player-star job: the orders it needs first, then the
// player's own day.
procedure ApplyPendingOrders;
procedure BeginSpaceDay;
// A save returns stock left by a shop the player has left, and runs mod OnSave handlers.
procedure PrepareSave;
procedure PrepareGalaxyForSave;
var
  // The days to land that the last PreparePlayerPath found, for the star map.
  PreparedLandingTurns: Integer;
implementation
uses
  SysUtils,
  Math,
  EC_Struct,
  aMyFunction,
  aCommands,
  aGalaxy,
  aPlanet,
  aPlayer,
  aSession,
  aHuman,
  aItem,
  aPath,
  aShopStock,
  aScript,
  aConst,
  aGalaxyStruct,
  ThreadCalc,
  Globals;

procedure AddWeaponSlot(var Slots: TSlotList; Slot: Integer);
begin
  SetLength(Slots, Length(Slots) + 1);
  Slots[High(Slots)] := Slot;
end;

function Actor(const Command: TPlayerCommand): TPlayer;
begin
  Result := GetPlayer;
end;

procedure ExecuteParkPlayer(const Command: TPlayerCommand);
var
  P: TPlayer;
  I: Integer;
begin
  P := Actor(Command);
  // This is deliberately a sandbox policy: the player stays docked and the
  // observer never writes a save. No landing/travel actions or quests are run.
  if P.InNormalSpace then
  begin
    P.CurrentPlanet := TPlanet(LocalHuman.PlayerStar.Planets[0]);
    P.DockedTo := nil;
  end;
  P.OrderNone(False);
  for I := 1 to P.WeaponCount do
    P.Weapons[I].Target := nil;
  LocalHuman.PlayerAutomaticControl := False;
  LocalHuman.PendingPlayerFollowTarget := nil;
  Session.PlayerStarDayPrepared := False;
end;

procedure ParkPlayer;
begin
  SubmitCommand(NewCommand(ckParkPlayer));
end;

procedure ExecutePruneMessages(const Command: TPlayerCommand);
begin
  PruneExpiredPersistentPlayerMessages;
end;

procedure PruneMessages;
begin
  SubmitCommand(NewCommand(ckPruneMessages));
end;

procedure ExecuteOrderStop(const Command: TPlayerCommand);
begin
  LocalHuman.PendingPlayerFollowTarget := nil;
  Actor(Command).OrderNone(False);
end;

procedure OrderStop;
begin
  SubmitCommand(NewCommand(ckOrderStop));
end;

function ShipPathNeedsPreparing(Ship: TShip): Boolean;
begin
  Result :=
      (Ship.Order in [soFollowShip, soLand, soJumpHole, soJump])
          or ((Ship = GetPlayer) and (LocalHuman.PendingPlayerFollowTarget <> nil))
          or ((Ship <> GetPlayer) and (Ship.Order = soMove));
end;

// Moved verbatim from TfStarMap.BuildShipPathOverlay.
function PrepareShipPath(Ship: TShip): Integer;
var
  Point, TargetPosition: TPointF;
  TargetShip, OtherShip: TShip;
  Distance, Angle, AngleOffset, Radius: Single;
  Index, Count: Integer;
begin
  Result := -1;
  if (Ship.Order = soFollowShip) or ((Ship = GetPlayer) and (LocalHuman.PendingPlayerFollowTarget <> nil)) then
  begin
    if (Ship = GetPlayer) and (LocalHuman.PendingPlayerFollowTarget <> nil) then
      TargetShip := LocalHuman.PendingPlayerFollowTarget
    else
      TargetShip := Ship.OrderTarget as TShip;
    if TargetShip.IsOnPlanet then
      TargetPosition := TargetShip.CurrentPlanet.GetPosition
    else
      TargetPosition := TargetShip.Position;
    Distance := PointDistance(Ship.Position, TargetShip.Position);
    AngleOffset := 0;
    Count := 0;
    while Count < 4 do
    begin
      Inc(Count);
      Radius := TargetShip.Graphic.Size.X / 2 + 20;
      if Distance < 1 then
      begin
        Angle :=
            HeadingDegreesToRadians(SeededRandomIntRange(0, 259, Ship.Seed * TargetShip.Seed))
                + AngleOffset;
        Point.X := TargetPosition.X + Sin(Angle) * Radius;
        Point.Y := TargetPosition.Y - Cos(Angle) * Radius;
      end
      else
      begin
        Angle :=
            ArcTan2(Ship.Position.X - TargetPosition.X, -(Ship.Position.Y - TargetPosition.Y))
                + AngleOffset;
        Point.X := TargetPosition.X + Sin(Angle) * Radius;
        Point.Y := TargetPosition.Y - Cos(Angle) * Radius;
      end;
      Index := 0;
      while Index < Ship.CurrentStar.Ships.Count do
      begin
        OtherShip := TShip(Ship.CurrentStar.Ships[Index]);
        if OtherShip.InNormalSpace and (PointDistanceSquared(Point, OtherShip.Position) < 900) then
          Break;
        Inc(Index);
      end;
      AngleOffset := AngleOffset + 1.5707963;
      if Index >= Ship.CurrentStar.Ships.Count then
        Break;
    end;
    Ship.OrderDestination := Point;
    Ship.ClearMovementPath;
    Ship.BuildFullPathTo(Ship.OrderDestination);
  end
  else if Ship.Order = soLand then
  begin
    Ship.ClearMovementPath;
    if (Ship = GetPlayer) and (Ship.OrderTarget is TPlanet) then
    begin
      Ship.BuildPlanetLandingPath;
      Result := Ship.GetMovementPathTurnCount;
      Ship.BuildFullPathTo(
          AddPointsF((Ship.OrderTarget as TPlanet).GetPosition, Ship.OrderDestination)
      );
    end
    else
    begin
      if Ship.OrderTarget is TShip then
        Ship.BuildFullPathTo(
            AddPointsF((Ship.OrderTarget as TShip).Position, Ship.OrderDestination)
        )
      else
        Ship.BuildFullPathTo(
            AddPointsF((Ship.OrderTarget as TPlanet).GetPosition, Ship.OrderDestination)
        );
    end;
  end
  else if Ship.Order = soJumpHole then
  begin
    Ship.ClearMovementPath;
    Ship.BuildFullPathTo(Ship.OrderDestination);
  end
  else if Ship.Order = soJump then
  begin
    Ship.ClearMovementPath;
    Ship.BuildOrderMovementPath(999999);
  end
  else if (Ship <> GetPlayer) and (Ship.Order = soMove) then
  begin
    Ship.ClearMovementPath;
    Ship.BuildFullPathTo(Ship.OrderDestination);
  end;
end;

procedure ExecutePreparePlayerPath(const Command: TPlayerCommand);
begin
  PreparedLandingTurns := PrepareShipPath(Actor(Command));
end;

procedure PreparePlayerPath;
begin
  SubmitCommand(NewCommand(ckPreparePlayerPath));
end;

procedure ExecuteBuildPlayerPath(const Command: TPlayerCommand);
begin
  Actor(Command).BuildOrderMovementPath(999999);
end;

procedure BuildPlayerPath;
begin
  SubmitCommand(NewCommand(ckBuildPlayerPath));
end;

// Moved verbatim from TfStarMap.MapLeftButtonDown.
procedure ExecuteOrderMove(const Command: TPlayerCommand);
var
  P: TPlayer;
  Flags: Integer;
  Node, FollowingNode: PSPathNode;
begin
  P := Actor(Command);
  Flags := IntArg(Command, 2);
  if (Flags and mfClearPending) <> 0 then
    LocalHuman.PendingPlayerFollowTarget := nil;
  P.OrderMove(PointArg(Command, 0), False);
  if (Flags and mfNoPath) = 0 then
    P.BuildOrderMovementPath(999999);
  if (Flags and mfCorrectEnd) <> 0 then
    if (P.MovementPath <> nil) and (P.MovementPath.ActiveHead <> nil) then
    begin
      Node := P.MovementPath.ActiveHead;
      while Node <> nil do
      begin
        FollowingNode := P.MovementPath.GetFollowingNode(Node, 198);
        if FollowingNode = nil then
          Break;
        if FollowingNode.Next = nil then
          Break;
        Node := FollowingNode.Next;
      end;
      if PointDistanceSquared(Node.Position, P.MovementPath.ActiveTail.Position) < 4900 then
      begin
        FollowingNode := Node;
        while (FollowingNode <> nil)
            and (PointDistanceSquared(FollowingNode.Position, Node.Position) < 25) do
          FollowingNode := FollowingNode.Prev;
        if FollowingNode <> nil then
        begin
          P.OrderMove(FollowingNode.Position, False);
          P.BuildOrderMovementPath(999999);
        end;
      end;
    end
    else
      P.OrderNone(False);
end;

procedure OrderMoveTo(const Destination: TPointF; Flags: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderMove);
  AddPoint(Command, Destination);
  AddInt(Command, Flags);
  SubmitCommand(Command);
end;

procedure ExecuteOrderLand(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  LocalHuman.PendingPlayerFollowTarget := nil;
  P.OrderLanding(RefObject(Command, 0), False);
  P.OrderDestination := PointArg(Command, 0);
end;

procedure OrderLandAt(Location: TObject; const Offset: TPointF);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderLand);
  AddRef(Command, Location);
  AddPoint(Command, Offset);
  SubmitCommand(Command);
end;

procedure ExecuteOrderJumpHole(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  LocalHuman.PendingPlayerFollowTarget := nil;
  P.OrderJumpHole(RefObject(Command, 0) as THole, False);
  P.OrderDestination := PointArg(Command, 0);
  P.BuildOrderMovementPath(999999);
end;

procedure OrderJumpThroughHole(Hole: TObject; const Destination: TPointF);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderJumpHole);
  AddRef(Command, Hole);
  AddPoint(Command, Destination);
  SubmitCommand(Command);
end;

procedure ExecuteOrderFollow(const Command: TPlayerCommand);
begin
  LocalHuman.PendingPlayerFollowTarget := nil;
  Actor(Command).OrderFollowShip(RefObject(Command, 0) as TShip, IntArg(Command, 0), False);
end;

procedure OrderFollow(Ship: TShip; Mode: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderFollow);
  AddRef(Command, Ship);
  AddInt(Command, Mode);
  SubmitCommand(Command);
end;

procedure ExecuteOrderAutoBattle(const Command: TPlayerCommand);
var
  Target: TObject;
begin
  Actor(Command).OrderNone(False);
  Target := RefObject(Command, 0);
  if Target <> nil then
    LocalHuman.PendingPlayerFollowTarget := Target as TShip;
end;

procedure OrderAutoBattle(Target: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderAutoBattle);
  AddRef(Command, Target);
  SubmitCommand(Command);
end;

procedure ExecuteSetWeaponTargets(const Command: TPlayerCommand);
var
  P: TPlayer;
  Target: TObject;
  I: Integer;
begin
  P := Actor(Command);
  Target := RefObject(Command, 0);
  for I := 0 to High(Command.Ints) do
    (P.FindEquippedItemInSlot(Ord(t_Weapon1), Command.Ints[I]) as TWeapon).Target := Target;
end;

procedure SetWeaponTargets(Target: TObject; const Slots: array of Integer);
var
  Command: TPlayerCommand;
  I: Integer;
begin
  if Length(Slots) = 0 then
    Exit;
  Command := NewCommand(ckSetWeaponTarget);
  AddRef(Command, Target);
  for I := 0 to High(Slots) do
    AddInt(Command, Slots[I]);
  SubmitCommand(Command);
end;

procedure ExecuteSetInterceptorTarget(const Command: TPlayerCommand);
begin
  Actor(Command).GetHull.InterceptorTarget := RefObject(Command, 0);
end;

procedure SetInterceptorTarget(Target: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetInterceptorTarget);
  AddRef(Command, Target);
  SubmitCommand(Command);
end;

procedure ExecuteSetPickupTarget(const Command: TPlayerCommand);
var
  P: TPlayer;
  Item: TItem;
begin
  P := Actor(Command);
  Item := RefObject(Command, 0) as TItem;
  if IntArg(Command, 0) <> 0 then
  begin
    if P.HasPickupTarget(Item) then
      P.RemovePickupTarget(Item);
    P.AddPickupTarget(Item, True);
  end
  else if P.HasPickupTarget(Item) then
    P.RemovePickupTarget(Item)
  else
    P.AddPickupTarget(Item, False);
end;

procedure TogglePickupTarget(Item: TObject);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetPickupTarget);
  AddRef(Command, Item);
  AddInt(Command, 0);
  SubmitCommand(Command);
end;

procedure PrioritizePickupTarget(Item: TObject);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetPickupTarget);
  AddRef(Command, Item);
  AddInt(Command, 1);
  SubmitCommand(Command);
end;

procedure ExecuteTogglePickupTargets(const Command: TPlayerCommand);
begin
  Actor(Command).TogglePickupTargets(IntArg(Command, 0) <> 0);
end;

procedure TogglePickupTargetsInRange(IgnoreRange: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTogglePickupTargets);
  AddInt(Command, Ord(IgnoreRange));
  SubmitCommand(Command);
end;

procedure ExecuteSetPendingFollow(const Command: TPlayerCommand);
begin
  LocalHuman.PendingPlayerFollowTarget := RefObject(Command, 0) as TShip;
end;

procedure SetPendingFollowTarget(Ship: TShip);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetPendingFollow);
  AddRef(Command, Ship);
  SubmitCommand(Command);
end;

// Moved verbatim from TfStarMap.OrderKeyDown.
procedure ExecuteSetAfterburner(const Command: TPlayerCommand);
var
  P: TPlayer;
  Index: Integer;
  Binding: TScriptShip;
begin
  P := Actor(Command);
  P.AfterburnerActive := IntArg(Command, 0) <> 0;
  P.RefreshDerivedStats(True);
  P.BuildOrderMovementPath(999999);
  if P.ScriptShipBindings <> nil then
  begin
    Index := P.ScriptShipBindings.Count - 1;
    while Index >= 0 do
    begin
      if Index >= P.ScriptShipBindings.Count then
        Index := P.ScriptShipBindings.Count - 1
      else
      begin
        Binding := TScriptShip(P.ScriptShipBindings[Index]);
        if Binding.Script <> nil then
          Binding.Script.RunShipState(Binding);
        Dec(Index);
      end;
    end;
  end;
end;

procedure SetAfterburner(Active: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckSetAfterburner);
  AddInt(Command, Ord(Active));
  SubmitCommand(Command);
end;

procedure ExecuteEnterRuinsMode(const Command: TPlayerCommand);
begin
  Actor(Command).EnterRuinsMode(IntArg(Command, 0));
end;

procedure EnterBridge(Mode: Integer);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckEnterRuinsMode);
  AddInt(Command, Mode);
  SubmitCommand(Command);
end;

procedure ExecuteExitRuinsMode(const Command: TPlayerCommand);
begin
  Actor(Command).ExitRuinsMode;
end;

procedure LeaveBridge;
begin
  SubmitCommand(NewCommand(ckExitRuinsMode));
end;

procedure ExecuteCancelInvalidTravelOrder(const Command: TPlayerCommand);
begin
  Actor(Command).CancelInvalidTravelOrder;
end;

procedure CancelInvalidTravelOrder;
begin
  SubmitCommand(NewCommand(ckCancelInvalidTravelOrder));
end;

procedure ExecuteRefreshStepParameters(const Command: TPlayerCommand);
begin
  LocalHuman.PlayerStar.RefreshMovementStepParameters;
end;

procedure RefreshPlayerStarSteps;
begin
  SubmitCommand(NewCommand(ckRefreshStepParameters));
end;

var
  ScriptItemsActResult: PtrInt;

procedure ExecuteScriptItemsAct(const Command: TPlayerCommand);
begin
  ScriptItemsActResult :=
      (RefObject(Command, 0) as TShip).ScriptItemsAct(
          IntArg(Command, 0),
          RefObject(Command, 1),
          RefObject(Command, 2),
          IntArg(Command, 1)
      );
end;

function RunScriptItemsAct(
    Ship: TShip;
    ActionType: Byte;
    Object1: TObject;
    Object2: TObject;
    Param: Integer
): PtrInt;
var
  Command: TPlayerCommand;
begin
  if not CanNameObject(Object1) or not CanNameObject(Object2) then
    Exit(Ship.ScriptItemsAct(ActionType, Object1, Object2, Param));
  Command := NewCommand(ckScriptItemsAct);
  AddRef(Command, Ship);
  AddRef(Command, Object1);
  AddRef(Command, Object2);
  AddInt(Command, ActionType);
  AddInt(Command, Param);
  SubmitCommand(Command);
  Result := ScriptItemsActResult;
end;

procedure ExecuteRunScriptTurns(const Command: TPlayerCommand);
var
  Index: Integer;
begin
  for Index := 0 to Galaxy.Scripts.Count - 1 do
    TScript(Galaxy.Scripts[Index]).RunTurnCode;
end;

procedure RunScriptTurns;
begin
  SubmitCommand(NewCommand(ckRunScriptTurns));
end;

// Moved from TfStarMap.ProcessTurnFilm.
procedure ExecuteLandingWear(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if (P.CurrentPlanet.OwnerId = Byte(oiUninhabited)) and (P.GetEngine <> nil) then
    P.ApplyItemDegradation(P.GetEngine, idkUse, NextRandomUnitFloat(P.RandomState) * 15);
end;

procedure ApplyLandingWear;
begin
  SubmitCommand(NewCommand(ckLandingWear));
end;

// Moved verbatim from TfStarMap.EndTurnClicked.
procedure ExecuteApplyPendingOrders(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  if P.CalculateSpeed = 0 then
    P.OrderNone(False);
  if LocalHuman.PendingPlayerFollowTarget <> nil then
    P.ProcessPendingPlayerFollowTargeting;
end;

procedure ApplyPendingOrders;
begin
  SubmitCommand(NewCommand(ckApplyPendingOrders));
end;

procedure ExecuteBeginSpaceDay(const Command: TPlayerCommand);
begin
  PruneExpiredPersistentPlayerMessages;
  LocalHuman.PlayerAutomaticControl := False;
  Actor(Command).NextDay;
end;

procedure BeginSpaceDay;
begin
  SubmitCommand(NewCommand(ckBeginSpaceDay));
end;

// Moved from aSaveLoad. Returns shop stock left behind by a shop the player is no longer
// at, and runs mod OnSave handlers.
procedure PrepareGalaxyForSave;
begin
  if (LocalHuman.TemporaryShopSlots <> nil)
      and (GetPlayer.CurrentPlanet <> LocalHuman.TemporaryShopPlanet)
      and (GetPlayer.DockedTo <> LocalHuman.TemporaryShopStation) then
    RestoreTemporaryShopStock;
  Galaxy.RunConfigOnSaveHandlers;
end;

procedure ExecutePrepareSave(const Command: TPlayerCommand);
begin
  PrepareGalaxyForSave;
end;

procedure PrepareSave;
begin
  SubmitCommand(NewCommand(ckPrepareSave));
end;

initialization
  RegisterCommand(ckParkPlayer, @ExecuteParkPlayer);
  RegisterCommand(ckPruneMessages, @ExecutePruneMessages);
  RegisterCommand(ckOrderStop, @ExecuteOrderStop);
  RegisterCommand(ckPreparePlayerPath, @ExecutePreparePlayerPath);
  RegisterCommand(ckBuildPlayerPath, @ExecuteBuildPlayerPath);
  RegisterCommand(ckOrderMove, @ExecuteOrderMove);
  RegisterCommand(ckOrderLand, @ExecuteOrderLand);
  RegisterCommand(ckOrderJumpHole, @ExecuteOrderJumpHole);
  RegisterCommand(ckOrderFollow, @ExecuteOrderFollow);
  RegisterCommand(ckOrderAutoBattle, @ExecuteOrderAutoBattle);
  RegisterCommand(ckSetWeaponTarget, @ExecuteSetWeaponTargets);
  RegisterCommand(ckSetInterceptorTarget, @ExecuteSetInterceptorTarget);
  RegisterCommand(ckSetPickupTarget, @ExecuteSetPickupTarget);
  RegisterCommand(ckTogglePickupTargets, @ExecuteTogglePickupTargets);
  RegisterCommand(ckApplyPendingOrders, @ExecuteApplyPendingOrders);
  RegisterCommand(ckBeginSpaceDay, @ExecuteBeginSpaceDay);
  RegisterCommand(ckPrepareSave, @ExecutePrepareSave);
  RegisterCommand(ckSetPendingFollow, @ExecuteSetPendingFollow);
  RegisterCommand(ckSetAfterburner, @ExecuteSetAfterburner);
  RegisterCommand(ckEnterRuinsMode, @ExecuteEnterRuinsMode);
  RegisterCommand(ckExitRuinsMode, @ExecuteExitRuinsMode);
  RegisterCommand(ckCancelInvalidTravelOrder, @ExecuteCancelInvalidTravelOrder);
  RegisterCommand(ckRefreshStepParameters, @ExecuteRefreshStepParameters);
  RegisterCommand(ckScriptItemsAct, @ExecuteScriptItemsAct);
  RegisterCommand(ckRunScriptTurns, @ExecuteRunScriptTurns);
  RegisterCommand(ckLandingWear, @ExecuteLandingWear);
end.
