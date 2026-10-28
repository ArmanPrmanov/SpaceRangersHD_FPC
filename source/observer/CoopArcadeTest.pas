{$EXCESSPRECISION OFF}
unit CoopArcadeTest;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - The co-op black hole battle's test (docs/network.md, Co-op black hole
// battles; tools/test.py, check_coop_arcade). Two game processes, each with a hidden window
// (SR_HIDDEN_WINDOW), load the same save with --load-save and --coop-arcade-test=host:PORT or
// join:PORT. Before the first screen, each one does the same: a second human joins at the
// first human's planet, and both rangers are put in one black hole. The host's local human is
// the first, the join's the second; they connect over a bare TNetConnection, and the battle
// runs in lockstep with a scripted input per participant (CoopLocalInputHook) until both send
// ciExit at tick --coop-arcade-ticks. Each prints its battle hashes ('coop hash tick=T
// hash=H'), and at the end its human's kill count, its hold and 'coop test done', and quits.
interface

var
  // 'host' or 'join'; '' when not testing.
  CoopTestRole: AnsiString;
  CoopTestPort: Integer;
  CoopTestTicks: Integer = 1500;

// From the screen loop, between two screens.
procedure CoopArcadeTestBetweenScreens;

implementation
uses
  SysUtils,
  Classes,
  EC_Buf,
  Globals,
  GlobalsV,
  GR_Main,
  aCalc,
  aConst,
  aGalaxy,
  aGalaxyStruct,
  aHuman,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aShip,
  aArcadeActions,
  ab_Coop,
  ab_Ship,
  NetTransport,
  NetProtocol,
  NetArcade;

const
  TestBattleSeed = 424242;
  ConnectWaitMs = 60000;

var
  Stage: Integer;
  Listener: TNetListener;
  Connection: TNetConnection;
  LocalId: Integer;
  KillsBefore, HoldBefore: Integer;

procedure Say(const Text: AnsiString);
begin
  WriteLn(Text);
  Flush(Output);
end;

procedure Fail(const Text: AnsiString);
begin
  Say('coop test failed: ' + Text);
  Halt(1);
end;

procedure PollConnection;
var
  Kind: TNetMessageKind;
  Payload: TBufEC;
begin
  if Connection = nil then
    Exit;
  Connection.Poll;
  Payload := TBufEC.Create;
  try
    while Connection.Receive(Kind, Payload) do
    begin
      if Kind = nkArcadeInput then
      begin
        Payload.SetPosition(0);
        StoreArcadeInput(DecodeArcadeInput(Payload));
      end;
      Payload.Clear;
    end;
  finally
    Payload.Free;
  end;
end;

procedure TestSend(Tick: Integer; const Input: TArcadeInput);
var
  Message: TArcadeInputMessage;
  Payload: TBufEC;
begin
  Message.Battle := CoopBattleSeed;
  Message.HumanId := LocalId;
  Message.Tick := Tick;
  Message.Buttons := Input.Buttons;
  Message.WeaponSelect := Input.WeaponSelect;
  Message.GroupToggles := Input.GroupToggles;
  Message.PickupObject := Input.PickupObject;
  StoreArcadeInput(Message);
  Payload := TBufEC.Create;
  try
    EncodeArcadeInput(Message, Payload);
    Connection.Send(nkArcadeInput, Payload);
  finally
    Payload.Free;
  end;
  Connection.Poll;
end;

function TestFetch(Tick, Participant: Integer; out Input: TArcadeInput): Boolean;
var
  Message: TArcadeInputMessage;
begin
  PollConnection;
  Input := EmptyArcadeInput;
  Result := FindArcadeInput(CoopBattleSeed, CoopHumanIds[Participant], Tick, Message);
  if Result then
  begin
    Input.Buttons := Message.Buttons;
    Input.WeaponSelect := Message.WeaponSelect;
    Input.GroupToggles := Message.GroupToggles;
    Input.PickupObject := Message.PickupObject;
  end;
end;

function TestGone(Participant: Integer): Boolean;
begin
  Result := (Participant <> CoopLocalIndex) and ((Connection = nil) or Connection.Closed);
end;

procedure TestHash(Tick: Integer; Hash: Cardinal);
var
  Own, Health, Weapons, I: Integer;
begin
  Own := -1;
  if (PlayerArcadeShip <> nil) and (PlayerArcadeShip.Enemies <> nil) then
    Own := PlayerArcadeShip.Enemies.Count;
  Say(Format('coop hash tick=%d hash=%.8x', [Tick, Hash]));
  Health := 0;
  Weapons := 0;
  if (PlayerArcadeShip <> nil) and (PlayerArcadeShip.Enemies <> nil) then
    for I := 0 to PlayerArcadeShip.Enemies.Count - 1 do
      if TObject(PlayerArcadeShip.Enemies[I]) is TabShip then
        Inc(Health, TabShip(PlayerArcadeShip.Enemies[I]).Health);
  if PlayerArcadeShip <> nil then
    Weapons := PlayerArcadeShip.WeaponCount;
  Say(Format('coop state tick=%d living=%d own-enemies=%d enemy-health=%d weapons=%d kills=%d',
      [Tick, CountLivingHumanEnemies, Own, Health, Weapons,
       LocalPlayer.BlackHoleKillCount - KillsBefore]));
end;

// Each participant's script: mostly the autopilot, with stretches of its own flying, firing
// and weapon choices that differ between the two, then the exit.
function TestInput(Tick: Integer): TArcadeInput;
var
  Phase: Integer;
begin
  Result := EmptyArcadeInput;
  if Tick >= CoopTestTicks then
  begin
    Result.Buttons := ciExit or ciAutopilot;
    Exit;
  end;
  Phase := (Tick div 100 + CoopLocalIndex) mod 4;
  case Phase of
    0:
      Result.Buttons := ciAutopilot;
    1:
      Result.Buttons := ciForward or ciTurnLeft or ciPrimaryFire;
    2:
      Result.Buttons := ciAutopilot or ciAltPickup;
    3:
      Result.Buttons := ciForward or ciTurnRight or ciSecondaryFire or ciPrimaryFire;
  end;
  if Tick mod 300 = 150 then
    Result.WeaponSelect := (Tick div 300 + CoopLocalIndex) mod 2;
end;

procedure TestPrepare;
begin
  // The test set the battle up itself.
end;

procedure TestFinish;
begin
end;

function FirstHole(Star: TStar): THole;
var
  I: Integer;
begin
  for I := 0 to Galaxy.Holes.Count - 1 do
    if Pos('SkipAB', THole(Galaxy.Holes[I]).ArcadeMapName) <> 1 then
      Exit(THole(Galaxy.Holes[I]));
  Result := THole.Create;
  Result.Id := $7E57;
  Result.Star1 := Star;
  Result.Star2 := Star;
  Result.HoleType := 1;
  Result.CreatedTurn := Galaxy.CurrentTurn;
  Result.ArcadeMapName := '';
  Galaxy.Holes.Add(Result);
end;

procedure PutInHole(P: TPlayer; Hole: THole);
begin
  P.TransitOriginStar := P.CurrentStar;
  P.Order := soJumpHole;
  P.OrderTarget := Hole;
  P.OrderStateData := 0;
  P.InHyperspace := True;
end;

function TotalHold(P: TPlayer): Integer;
begin
  Result := P.Inventory.Count + P.Artefacts.Count;
end;

procedure Connect;
var
  Started: QWord;
begin
  Started := GetTickCount64;
  if CoopTestRole = 'host' then
  begin
    Listener := TNetListener.Create(CoopTestPort);
    repeat
      Connection := Listener.Accept;
      if Connection = nil then
        Sleep(20);
    until (Connection <> nil) or (GetTickCount64 - Started > ConnectWaitMs);
  end
  else
    repeat
      Connection := TNetConnection.Connect('127.0.0.1', CoopTestPort, 2000);
      if Connection = nil then
        Sleep(200);
    until (Connection <> nil) or (GetTickCount64 - Started > ConnectWaitMs);
  if Connection = nil then
    Fail('no connection');
  Say('coop test connected');
end;

procedure Finish; forward;

procedure SetUp;
var
  A, B: THuman;
  Planet: TPlanet;
  Hole: THole;
begin
  aCalc.WaitForTurnCalculationUI;
  A := LocalHuman;
  Planet := A.Player.CurrentPlanet;
  if (Planet = nil) and (A.Player.CurrentStar <> nil) and (A.Player.CurrentStar.Planets.Count > 0) then
    Planet := A.Player.CurrentStar.Planets[0];
  if Planet = nil then
    Fail('the ranger is at no planet');
  B := JoinHumanAt(Planet, 'CoopB', 2);
  if B = nil then
    Fail('the second human did not join');
  Hole := FirstHole(A.Player.CurrentStar);
  PutInHole(A.Player, Hole);
  PutInHole(B.Player, Hole);
  CoopParticipantCount := 2;
  CoopHumanIds[0] := A.Id;
  CoopHumanIds[1] := B.Id;
  if CoopTestRole = 'host' then
    CoopLocalIndex := 0
  else
  begin
    CoopLocalIndex := 1;
    SetLocalHuman(B);
  end;
  LocalId := CoopHumanIds[CoopLocalIndex];
  CoopBattleSeed := TestBattleSeed;
  KillsBefore := LocalPlayer.BlackHoleKillCount;
  HoldBefore := TotalHold(LocalPlayer);
  KeepOnlyArcadeBattle(CoopBattleSeed);
  BeginArcadeLoot([A.Player, B.Player]);
  CoopPrepareHook := @TestPrepare;
  CoopFinishHook := @TestFinish;
  CoopSendHook := @TestSend;
  CoopFetchHook := @TestFetch;
  CoopGoneHook := @TestGone;
  CoopHashHook := @TestHash;
  CoopLocalInputHook := @TestInput;
  // The test ends at the exit, before the jump's day: its rangers were put in the hole by hand.
  CoopLocalExitHook := @Finish;
  CoopArcadeActive := True;
  if Pos('SkipAB', Hole.ArcadeMapName) = 1 then
    ArcadeBattleScreen.SelectedMapName := ''
  else
    ArcadeBattleScreen.SelectedMapName := Hole.ArcadeMapName;
  Say(Format('coop test battle humans=%d,%d local=%d hole=%d',
      [A.Id, B.Id, CoopLocalIndex, Integer(Hole.Id)]));
  RequestedScreenId := screenArcadeBattle;
end;

procedure Finish;
begin
  Say(Format('coop test result kills=%d hold=%d hull=%d',
      [LocalPlayer.BlackHoleKillCount - KillsBefore, TotalHold(LocalPlayer) - HoldBefore,
       LocalPlayer.GetHull.HullPoints]));
  if Connection <> nil then
  begin
    Connection.FlushAll(2000);
    Connection.Close;
  end;
  Say('coop test done');
  Halt(0);
end;

procedure CoopArcadeTestBetweenScreens;
begin
  if CoopTestRole = '' then
    Exit;
  case Stage of
    0:
      if (Galaxy <> nil) and (LocalPlayer <> nil)
          and (RequestedScreenId
              in [screenStarMap, screenPlanet, screenPlanetNO, screenRuinsTalk, screenHangar]) then
      begin
        Stage := 1;
        Connect;
        SetUp;
      end;
    1:
      if RequestedScreenId <> screenArcadeBattle then
        Finish;
  end;
end;

end.
