{$EXCESSPRECISION OFF}
unit ab_Coop;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - A black hole battle that two humans fight together, in real time
// (docs/network.md, Co-op black hole battles). Each participant's machine runs the whole
// battle in lockstep: the simulation is deterministic, and a tick runs only when every
// participant's input for it has come. The input of tick T is sampled at tick T - InputDelay
// and sent at once, which hides the round trip.
//
// The arcade layer uses only this unit; the network session (NetPlay) sets the hooks. A
// battle without them (or with CoopArcadeActive false) is the original single-player one.
//
// What is deterministic, and why:
// - Every machine is the same Windows x64 binary with {$EXCESSPRECISION OFF}, so the same
//   Double/Single operations in the same order give the same bits.
// - The battle is built from CoopBattleSeed (TfAB.RandomSeed) and from the leader's ranger
//   (CoopGenerationPlayer), never from LocalPlayer; the participants' ships are created in
//   participant order, before the encounter, so every TabObject gets the same CoopId and
//   InitialRandomSeed everywhere, and the one object list keeps the same order.
// - The simulation's draws that used the presentation stream (RandomIntRange, System.Random)
//   go through CoopRandomRange/CoopRandom/CoopRandomFloat, one stream seeded from
//   CoopBattleSeed. Visual-only draws stay on the presentation stream.
// - A tick T runs only with every participant's input of T (TArcadeInput), applied in
//   participant order to that participant's ship (CoopShips): keys, its own autopilot flag,
//   weapon choice, group toggles, cargo pickups (by CoopId), Alt pickups and its exit. The
//   autopilot idle timer, the keys and Alt are sampled locally, outside the simulation.
// - Nothing else local feeds the simulation: a dying object is deleted a fixed number of
//   ticks after its death (CoopExpireTick) instead of when its explosion animation ends or
//   when it is behind this camera's horizon; the explosions play on and are freed by
//   themselves. Pause, the equipment screen and the overlap repulsion outside a tick are off;
//   the bonus spawner and Alt pickups run inside the tick.
// - Kills count for every participant's ranger on every machine; each kill draws its reward's
//   recipient from the co-op stream on every machine, and only the recipient's machine makes
//   and stores the item (it uses the galaxy's streams, which no arcade rule reads, and it puts
//   back the dying ship's own stream).
// - Bonuses and cargo go to the ship (and the participant's TPlayer) that picked them up.
//
// What is not, or is only as good as its inputs:
// - Every participant's TPlayer must be the same on every machine when the battle opens (the
//   galaxy is shared): hull, weapons, artefacts, cargo hook, kill counts.
// - Item scripts run at the ship's creation (RunScriptItemsAct) and on reward drops; they are
//   assumed to touch only their own ranger's data.
// - Cheats (CheatCode, GodModEnabled/AmmoModEnabled) and the Ctrl+Shift+Alt debug keys act on
//   one machine only.
// - Keller encounters and scripted battles are never co-op (the caller excludes them).
// - A participant that the network reports gone flies by autopilot from the tick this machine
//   notices it: the machines can then disagree, but no machine runs the battle with it any
//   more.
interface
uses
  aPlayer;

const
  // At most this many participants.
  CoopMaxParticipants = 2;
  // A tick's input is sampled this many ticks before it runs (20 ms each).
  CoopInputDelay = 4;
  // TArcadeInput.Buttons.
  ciForward = 1;
  ciReverse = 2;
  ciBrake = 4;
  ciTurnLeft = 8;
  ciTurnRight = 16;
  ciPrimaryFire = 32;
  ciSecondaryFire = 64;
  // The ship flies itself (the autopilot: the player's choice or its idle timer).
  ciAutopilot = 128;
  // Alt held: cargo within reach is picked up.
  ciAltPickup = 256;
  // The participant leaves the battle at this tick (its exit, or its defeat's end).
  ciExit = 512;
  // A dying ship or barrier is deleted this many ticks after its death.
  CoopDeathTicks = 50;
  // An exploding projectile is deleted this many ticks after its explosion starts.
  CoopProjectileExpireTicks = 30;
  // The stall after which the waiting text shows (timer fires of 20 ms).
  CoopStallNoticeFires = 50;

type
  // One participant's input for one tick.
  TArcadeInput = packed record
    Buttons: Word;
    // The weapon slot (0-4) to select at this tick; -1 for none.
    WeaponSelect: ShortInt;
    // Bit I: toggle the secondary group of weapon slot I at this tick.
    GroupToggles: Byte;
    // The arcade object (TabObject.CoopId) a click asks to pick up; 0 for none.
    PickupObject: Integer;
  end;
  PArcadeInput = ^TArcadeInput;

  // The local input of Tick goes to the other participants. Called once per tick, in tick
  // order, from Tick = CoopInputDelay + 1 on.
  TCoopSendHook = procedure(Tick: Integer; const Input: TArcadeInput);
  // Participant's input of Tick, when it has come; False while it has not. Never asked for
  // the local participant (the arcade keeps its own inputs) nor for ticks <= CoopInputDelay
  // (they are empty everywhere). Without a fetch hook every other participant counts as gone.
  TCoopFetchHook = function(Tick, Participant: Integer; out Input: TArcadeInput): Boolean;
  // Whether Participant has left the session (disconnected): its ship then flies by
  // autopilot from the tick this machine notices it, since no other machine runs the battle
  // with it any more. Asked only while its input is missing.
  TCoopGoneHook = function(Participant: Integer): Boolean;
  // The battle's state hash every CoopHashInterval ticks, for the tests.
  TCoopHashHook = procedure(Tick: Integer; Hash: Cardinal);
  // The tests' driver: the local input of Tick instead of the keys and the autopilot timer
  // (the local exit request is still added to it).
  TCoopLocalInputHook = function(Tick: Integer): TArcadeInput;
  // Called by TfAB.OnOpen before the battle's seed is chosen, for a black hole battle without
  // a script request: decides whether it is co-op and sets the variables and hooks below.
  TCoopPrepareHook = procedure;
  // Called once when the co-op battle's screen closes; CoopArcadeActive is cleared after it.
  // Also called at once (with CoopArcadeActive already false) when OnOpen cannot find a
  // participant's ranger and the battle is fought alone.
  TCoopFinishHook = procedure;
  // Called right after the local participant's exit (its loot and exit commands have run).
  TCoopLocalExitHook = procedure;

const
  CoopHashInterval = 50;

var
  // A co-op battle is open (set by CoopPrepareHook, cleared when TfAB closes).
  CoopArcadeActive: Boolean;
  CoopParticipantCount: Integer;
  // The participants' humans, in the order every machine creates their ships (Session.Humans
  // order); the first is the battle's leader, whose ranger the encounter is built for.
  CoopHumanIds: array[0..CoopMaxParticipants - 1] of Integer;
  // This machine's participant.
  CoopLocalIndex: Integer;
  // The seed every machine starts the battle's random streams from.
  CoopBattleSeed: Cardinal;
  CoopSendHook: TCoopSendHook;
  CoopFetchHook: TCoopFetchHook;
  CoopGoneHook: TCoopGoneHook;
  CoopHashHook: TCoopHashHook;
  CoopLocalInputHook: TCoopLocalInputHook;
  CoopPrepareHook: TCoopPrepareHook;
  CoopFinishHook: TCoopFinishHook;
  CoopLocalExitHook: TCoopLocalExitHook;

  // Set by the arcade when the battle opens (CoopBeginBattle).
  // The participants' rangers (FindHuman(CoopHumanIds[I]).Player).
  CoopPlayers: array[0..CoopMaxParticipants - 1] of TPlayer;
  // The participant's ciExit has run: its ship is out of the battle.
  CoopLeft: array[0..CoopMaxParticipants - 1] of Boolean;
  // The network reported the participant gone: its ship flies by autopilot.
  CoopGone: array[0..CoopMaxParticipants - 1] of Boolean;
  // The participant holds Alt at the running tick (its ciAltPickup), for ab_Item_Update.
  CoopAltHeld: array[0..CoopMaxParticipants - 1] of Boolean;
  // The participant whose input this machine waits for; -1 while the battle is not stalled.
  CoopWaitingFor: Integer = -1;
  // The battle's simulation is running (opened, and this machine's participant has not left).
  CoopBattleRunning: Boolean;

function EmptyArcadeInput: TArcadeInput;
// The battle's own random stream, for the simulation's draws that used the presentation
// stream (RandomIntRange): seeded from CoopBattleSeed, so every machine draws the same.
// Outside a co-op battle it is RandomIntRange.
function CoopRandomRange(BoundA, BoundB: Integer): Integer;
// System.Random(Range) in the simulation, the same way.
function CoopRandom(Range: Integer): Integer;
// System.Random (a float in [0, 1)) in the simulation, the same way.
function CoopRandomFloat: Double;
// The co-op stream's state, for the state hash.
function CoopRandomStateValue: Cardinal;
// Restarts the stream at a battle's start.
procedure ResetCoopRandom;
// The ranger the battle is generated for: the leader's in a co-op battle, else LocalPlayer.
function CoopGenerationPlayer: TPlayer;
// Resolves CoopPlayers and clears the battle's state; False (and CoopArcadeActive cleared)
// when a participant cannot be found. Called by TfAB.OnOpen after CoopPrepareHook.
function CoopBeginBattle: Boolean;
// The next TabObject.CoopId (1, 2, ...); restarted by CoopBeginBattle and ResetCoopObjectIds.
function NextCoopObjectId: Integer;
procedure ResetCoopObjectIds;
// The local input of Tick, kept for when Tick runs (the arcade does not ask the fetch hook
// for its own participant).
procedure CoopStoreLocalInput(Tick: Integer; const Input: TArcadeInput);
function CoopLocalInput(Tick: Integer): TArcadeInput;
// The battle's current tick (ArcadeTickCount) and whether its simulation still runs here,
// for a test driver.
function CoopBattleTick(out Running: Boolean): Integer;
// FNV-1a over the state hash's values.
procedure CoopHashBytes(var Hash: Cardinal; const Data; Size: Integer);
procedure CoopHashInteger(var Hash: Cardinal; Value: Integer);
procedure CoopHashDouble(var Hash: Cardinal; Value: Double);

implementation
uses
  aMyFunction,
  aHuman,
  ab_Global;

const
  CoopLocalInputRing = 256;

var
  CoopRandomState: Cardinal;
  CoopObjectCounter: Integer;
  CoopLocalInputs: array[0..CoopLocalInputRing - 1] of TArcadeInput;
  CoopLocalInputTicks: array[0..CoopLocalInputRing - 1] of Integer;

function EmptyArcadeInput: TArcadeInput;
begin
  Result.Buttons := 0;
  Result.WeaponSelect := -1;
  Result.GroupToggles := 0;
  Result.PickupObject := 0;
end;

procedure ResetCoopRandom;
begin
  CoopRandomState := CoopBattleSeed xor $9E3779B9;
  if CoopRandomState = 0 then
    CoopRandomState := 1;
end;

// xorshift32.
function NextCoopRandom: Cardinal;
begin
  CoopRandomState := CoopRandomState xor (CoopRandomState shl 13);
  CoopRandomState := CoopRandomState xor (CoopRandomState shr 17);
  CoopRandomState := CoopRandomState xor (CoopRandomState shl 5);
  Result := CoopRandomState;
end;

function CoopRandomRange(BoundA, BoundB: Integer): Integer;
var
  Low, High: Integer;
begin
  if not CoopArcadeActive then
    Exit(RandomIntRange(BoundA, BoundB));
  if BoundA <= BoundB then
  begin
    Low := BoundA;
    High := BoundB;
  end
  else
  begin
    Low := BoundB;
    High := BoundA;
  end;
  Result := Low + Integer(NextCoopRandom mod Cardinal(Int64(High) - Low + 1));
end;

function CoopRandom(Range: Integer): Integer;
begin
  if not CoopArcadeActive then
    Exit(System.Random(Range));
  if Range <= 0 then
    Exit(0);
  Result := Integer(NextCoopRandom mod Cardinal(Range));
end;

function CoopRandomFloat: Double;
begin
  if not CoopArcadeActive then
    Exit(System.Random);
  Result := (NextCoopRandom shr 8) / 16777216.0;
end;

function CoopRandomStateValue: Cardinal;
begin
  Result := CoopRandomState;
end;

function CoopGenerationPlayer: TPlayer;
begin
  if CoopArcadeActive and (CoopPlayers[0] <> nil) then
    Result := CoopPlayers[0]
  else
    Result := LocalPlayer;
end;

function CoopBeginBattle: Boolean;
var
  Index: Integer;
  Human: THuman;
begin
  Result := False;
  for Index := 0 to CoopMaxParticipants - 1 do
  begin
    CoopPlayers[Index] := nil;
    CoopLeft[Index] := False;
    CoopGone[Index] := False;
    CoopAltHeld[Index] := False;
  end;
  for Index := 0 to CoopLocalInputRing - 1 do
    CoopLocalInputTicks[Index] := -1;
  CoopWaitingFor := -1;
  CoopBattleRunning := False;
  if not CoopArcadeActive then
    Exit;
  if (CoopParticipantCount < 1)
      or (CoopParticipantCount > CoopMaxParticipants)
      or (CoopLocalIndex < 0)
      or (CoopLocalIndex >= CoopParticipantCount) then
  begin
    CoopArcadeActive := False;
    Exit;
  end;
  for Index := 0 to CoopParticipantCount - 1 do
  begin
    Human := FindHuman(CoopHumanIds[Index]);
    if (Human = nil) or (Human.Player = nil) then
    begin
      CoopArcadeActive := False;
      Exit;
    end;
    CoopPlayers[Index] := Human.Player;
  end;
  ResetCoopRandom;
  ResetCoopObjectIds;
  CoopBattleRunning := True;
  Result := True;
end;

function NextCoopObjectId: Integer;
begin
  Inc(CoopObjectCounter);
  Result := CoopObjectCounter;
end;

procedure ResetCoopObjectIds;
begin
  CoopObjectCounter := 0;
end;

procedure CoopStoreLocalInput(Tick: Integer; const Input: TArcadeInput);
begin
  CoopLocalInputs[Tick and (CoopLocalInputRing - 1)] := Input;
  CoopLocalInputTicks[Tick and (CoopLocalInputRing - 1)] := Tick;
end;

function CoopLocalInput(Tick: Integer): TArcadeInput;
begin
  if CoopLocalInputTicks[Tick and (CoopLocalInputRing - 1)] = Tick then
    Result := CoopLocalInputs[Tick and (CoopLocalInputRing - 1)]
  else
    Result := EmptyArcadeInput;
end;

function CoopBattleTick(out Running: Boolean): Integer;
begin
  Running := CoopArcadeActive and CoopBattleRunning;
  Result := ArcadeTickCount;
end;

procedure CoopHashBytes(var Hash: Cardinal; const Data; Size: Integer);
var
  Bytes: PByte;
  Index: Integer;
begin
  Bytes := @Data;
  for Index := 0 to Size - 1 do
  begin
    Hash := (Hash xor Bytes[Index]) * 16777619;
  end;
end;

procedure CoopHashInteger(var Hash: Cardinal; Value: Integer);
begin
  CoopHashBytes(Hash, Value, SizeOf(Value));
end;

procedure CoopHashDouble(var Hash: Cardinal; Value: Double);
begin
  CoopHashBytes(Hash, Value, SizeOf(Value));
end;

end.
