{$EXCESSPRECISION OFF}
unit aPlayerActions;

// CHANGE: ENHANCEMENT - What a human does to the game, as commands (aCommands). The UI calls
// the procedures in the interface; each builds a command and submits it, and the executor
// below does what the UI used to do itself. The executors take the acting ranger from the
// command, never from the screen.
interface
uses
  Types,
  aCommands,
  aShip;
const
  // Command kinds 0-99 (see TCommandKind).
  ckBeginSpaceDay = 1;
  ckPrepareSave = 2;
  ckPruneMessages = 3;
  ckParkPlayer = 4;
  ckPreparePlayerPath = 5;
  ckApplyPendingOrders = 6;
  ckBuildPlayerPath = 7;
  ckOrderMove = 10;
  ckOrderStop = 11;
  ckOrderFollow = 12;
  ckOrderAutoBattle = 13;
  ckOrderLand = 14;
  ckOrderJumpHole = 15;
  ckOrderJump = 16;
  ckSetWeaponTarget = 17;
  ckSetPickupTarget = 19;
  ckTogglePickupTargets = 20;
  ckSetAfterburner = 21;
  ckSetInterceptorTarget = 22;
  ckSetPendingFollow = 23;
  ckEnterRuinsMode = 24;
  ckExitRuinsMode = 25;
  ckCancelInvalidTravelOrder = 26;
  ckRefreshStepParameters = 27;
  ckScriptItemsAct = 28;
  ckRunScriptTurns = 29;
  ckLandingWear = 30;
  ckOrderNone = 31;
  ckTakeoff = 32;
  ckHyperspaceStep = 33;
  ckCreateJumpHole = 34;
  ckOrderTeleport = 35;
  ckReturnShopStock = 36;
  ckOpenShopStock = 37;
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
procedure OrderNone;
// Jumps to Star and forgets a pending auto-battle target.
procedure OrderJumpTo(Star: TObject);
procedure OrderTeleportTo(Star: TObject);
// Opens a black hole from the player's position to Star and heads into it (the Star
// Destroyer's bridge). Returns the hole.
function CreateJumpHoleTo(Star: TObject): TObject;

const
  // Takeoff flags.
  tfEndAutomaticControl = 1;
  tfReturnShopStock = 2;
  // Keep the player docked when the takeoff order does not take.
  tfStopWithoutOrder = 4;
// Leaves the planet or station: the takeoff order, the scripts that react to it and the
// star's objects. Returns whether the player took off.
function Takeoff(Flags: Integer): Boolean;
// A hyperspace day passed: the human's star becomes the one the player is now in.
// SetInHyperspace is for the arcade battle, which ends outside hyperspace.
procedure HyperspaceStep(SetInHyperspace: Boolean);
procedure ReturnShopStock;
procedure OpenShopStock;

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
  aGalaxyEvent,
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

procedure ExecuteOrderNone(const Command: TPlayerCommand);
begin
  Actor(Command).OrderNone(False);
end;

procedure OrderNone;
begin
  SubmitCommand(NewCommand(ckOrderNone));
end;

procedure ExecuteOrderJump(const Command: TPlayerCommand);
begin
  Actor(Command).OrderJump(RefObject(Command, 0) as TStar, False);
  LocalHuman.PendingPlayerFollowTarget := nil;
end;

procedure OrderJumpTo(Star: TObject);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderJump);
  AddRef(Command, Star);
  SubmitCommand(Command);
end;

procedure ExecuteOrderTeleport(const Command: TPlayerCommand);
var
  P: TPlayer;
begin
  P := Actor(Command);
  P.OrderTeleport(RefObject(Command, 0) as TStar, P.Position, 10, False);
  LocalHuman.PendingPlayerFollowTarget := nil;
end;

procedure OrderTeleportTo(Star: TObject);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOrderTeleport);
  AddRef(Command, Star);
  SubmitCommand(Command);
end;

var
  CreatedHole: THole;

// Moved from TfGalaxy2.JumpClicked; the screen sets the hole's look.
procedure ExecuteCreateJumpHole(const Command: TPlayerCommand);
var
  P: TPlayer;
  Hole: THole;
  Angle, Radius: Double;
  Event: TGalaxyEvent;
begin
  P := Actor(Command);
  Hole := THole.Create;
  Hole.InitializeGraphic('');
  Hole.Star1 := P.CurrentStar;
  Angle := ArcTan2(P.Position.X, -P.Position.Y);
  Radius :=
      Max(
          P.CurrentStar.SafeRadius + 100,
          Sqrt(PointDistanceSquared(P.Position, MakePointF(0, 0))) + 200
      );
  Hole.Position1 := MakePointF(Sin(Angle) * Radius, -Cos(Angle) * Radius);
  Hole.Star2 := RefObject(Command, 0) as TStar;
  Angle := HeadingDegreesToRadians(SeededRandomIntRange(0, 359, Galaxy.RandomState));
  Radius := SeededRandomIntRange(1000, 2000, Galaxy.RandomState);
  Hole.Position2 := MakePointF(Sin(Angle) * Radius, -Cos(Angle) * Radius);
  Hole.CreatedTurn := Galaxy.CurrentTurn - 190;
  Hole.HoleType := 1;
  Galaxy.Holes.Add(Hole);
  Hole.ArcadeMapName := 'SkipAB';
  P.OrderJumpHole(Hole, False);
  P.GetHull.Energy := Max(0, P.GetHull.Energy - 600);
  Event := AddGalaxyEvent('PlayerCreatedStarDestroyerBH');
  Event.AddData(Hole.Id);
  Event.AddData(Hole.CreatedTurn);
  LocalHuman.PendingPlayerFollowTarget := nil;
  CreatedHole := Hole;
end;

function CreateJumpHoleTo(Star: TObject): TObject;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckCreateJumpHole);
  AddRef(Command, Star);
  SubmitCommand(Command);
  Result := CreatedHole;
end;

var
  TookOff: Boolean;

// Moved from TfHangar.TryTakeOff, TfPlanetNO.TakeoffClicked and
// TfPanelRuins.TakeOffForStationTravel, which differ only in the flags.
procedure ExecuteTakeoff(const Command: TPlayerCommand);
var
  P: TPlayer;
  Flags, I: Integer;
begin
  P := Actor(Command);
  Flags := IntArg(Command, 0);
  if (Flags and tfEndAutomaticControl) <> 0 then
    LocalHuman.PlayerAutomaticControl := False;
  PruneExpiredPersistentPlayerMessages;
  P.OrderTakeoff;
  TookOff := P.Order = soTakeoff;
  if not TookOff and ((Flags and tfStopWithoutOrder) <> 0) then
    Exit;
  for I := 0 to Galaxy.Scripts.Count - 1 do
    TScript(Galaxy.Scripts[I]).RunTurnCode;
  LocalHuman.PlayerStar.RefreshSpaceObjectPositions;
  if (Flags and tfReturnShopStock) <> 0 then
    RestoreTemporaryShopStock;
  RunGlobalScriptsForContext(P.CurrentStar, 1);
  if (GetPlayer <> nil) and GetPlayer.IsHealthEffectActive(3) then
    Galaxy.EnableDominatorSurfaces
  else
    Galaxy.DisableDominatorSurfaces;
end;

function Takeoff(Flags: Integer): Boolean;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckTakeoff);
  AddInt(Command, Flags);
  SubmitCommand(Command);
  Result := TookOff;
end;

// Moved from TfJump.AdvanceTravel and TfAB.FinishCampaignTransition; the screens draw the
// new star's background.
procedure ExecuteHyperspaceStep(const Command: TPlayerCommand);
var
  P: TPlayer;
  PreviousStar: TStar;
begin
  P := Actor(Command);
  Galaxy.ClearJumpGates;
  PreviousStar := LocalHuman.PlayerStar;
  LocalHuman.PlayerStar := P.CurrentStar;
  LocalHuman.PlayerStar.RebuildShipMovementPaths;
  PreviousStar.RebuildShipMovementPaths;
  if (Cardinal(P.OrderStateData) and $FFFF) = 1 then
  begin
    PruneExpiredPersistentPlayerMessages;
    RunGlobalScriptsForContext(P.CurrentStar, 3);
  end;
  if IntArg(Command, 0) <> 0 then
    P.InHyperspace := True;
end;

procedure HyperspaceStep(SetInHyperspace: Boolean);
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckHyperspaceStep);
  AddInt(Command, Ord(SetInHyperspace));
  SubmitCommand(Command);
end;

procedure ExecuteReturnShopStock(const Command: TPlayerCommand);
begin
  RestoreTemporaryShopStock;
end;

procedure ReturnShopStock;
begin
  SubmitCommand(NewCommand(ckReturnShopStock));
end;

// The grid is padded to the columns the shop screen shows, so the command carries them.
procedure ExecuteOpenShopStock(const Command: TPlayerCommand);
begin
  ShopVisibleColumnCount := IntArg(Command, 0);
  BuildTemporaryShopSlotGrid;
end;

procedure OpenShopStock;
var
  Command: TPlayerCommand;
begin
  Command := NewCommand(ckOpenShopStock);
  AddInt(Command, ShopVisibleColumnCount);
  SubmitCommand(Command);
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
  RegisterCommand(ckParkPlayer, 'ParkPlayer', @ExecuteParkPlayer);
  RegisterCommand(ckPruneMessages, 'PruneMessages', @ExecutePruneMessages);
  RegisterCommand(ckOrderStop, 'OrderStop', @ExecuteOrderStop);
  RegisterCommand(ckPreparePlayerPath, 'PreparePlayerPath', @ExecutePreparePlayerPath);
  RegisterCommand(ckBuildPlayerPath, 'BuildPlayerPath', @ExecuteBuildPlayerPath);
  RegisterCommand(ckOrderMove, 'OrderMove', @ExecuteOrderMove);
  RegisterCommand(ckOrderLand, 'OrderLand', @ExecuteOrderLand);
  RegisterCommand(ckOrderJumpHole, 'OrderJumpHole', @ExecuteOrderJumpHole);
  RegisterCommand(ckOrderFollow, 'OrderFollow', @ExecuteOrderFollow);
  RegisterCommand(ckOrderAutoBattle, 'OrderAutoBattle', @ExecuteOrderAutoBattle);
  RegisterCommand(ckSetWeaponTarget, 'SetWeaponTarget', @ExecuteSetWeaponTargets);
  RegisterCommand(ckSetInterceptorTarget, 'SetInterceptorTarget', @ExecuteSetInterceptorTarget);
  RegisterCommand(ckSetPickupTarget, 'SetPickupTarget', @ExecuteSetPickupTarget);
  RegisterCommand(ckTogglePickupTargets, 'TogglePickupTargets', @ExecuteTogglePickupTargets);
  RegisterCommand(ckApplyPendingOrders, 'ApplyPendingOrders', @ExecuteApplyPendingOrders);
  RegisterCommand(ckBeginSpaceDay, 'BeginSpaceDay', @ExecuteBeginSpaceDay);
  RegisterCommand(ckPrepareSave, 'PrepareSave', @ExecutePrepareSave);
  RegisterCommand(ckSetPendingFollow, 'SetPendingFollow', @ExecuteSetPendingFollow);
  RegisterCommand(ckSetAfterburner, 'SetAfterburner', @ExecuteSetAfterburner);
  RegisterCommand(ckEnterRuinsMode, 'EnterRuinsMode', @ExecuteEnterRuinsMode);
  RegisterCommand(ckExitRuinsMode, 'ExitRuinsMode', @ExecuteExitRuinsMode);
  RegisterCommand(ckCancelInvalidTravelOrder, 'CancelInvalidTravelOrder', @ExecuteCancelInvalidTravelOrder);
  RegisterCommand(ckRefreshStepParameters, 'RefreshStepParameters', @ExecuteRefreshStepParameters);
  RegisterCommand(ckScriptItemsAct, 'ScriptItemsAct', @ExecuteScriptItemsAct);
  RegisterCommand(ckRunScriptTurns, 'RunScriptTurns', @ExecuteRunScriptTurns);
  RegisterCommand(ckLandingWear, 'LandingWear', @ExecuteLandingWear);
  RegisterCommand(ckOrderNone, 'OrderNone', @ExecuteOrderNone);
  RegisterCommand(ckOrderJump, 'OrderJump', @ExecuteOrderJump);
  RegisterCommand(ckOrderTeleport, 'OrderTeleport', @ExecuteOrderTeleport);
  RegisterCommand(ckCreateJumpHole, 'CreateJumpHole', @ExecuteCreateJumpHole);
  RegisterCommand(ckTakeoff, 'Takeoff', @ExecuteTakeoff);
  RegisterCommand(ckHyperspaceStep, 'HyperspaceStep', @ExecuteHyperspaceStep);
  RegisterCommand(ckReturnShopStock, 'ReturnShopStock', @ExecuteReturnShopStock);
  RegisterCommand(ckOpenShopStock, 'OpenShopStock', @ExecuteOpenShopStock);
end.
