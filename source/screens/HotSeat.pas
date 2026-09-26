{$EXCESSPRECISION OFF}
unit HotSeat;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - Hot-seat (ROADMAP.md, Phase 4 and Milestone 3): several humans take
// turns at one machine and one screen. --hotseat=N adds humans after a game loads or starts.
// A day runs only when no human holds it (aHuman.HumanHoldsDay). When the local human ends its
// turn and another human still holds the day, the screen passes to the first such human in
// Session.Humans order, who becomes the local human (aHuman.SetLocalHuman); the day runs on the
// screen of the human who ends the turn last. See docs/humans.md, End turn and hot-seat.
interface
uses
  GI_MessageLoop,
  aHuman;
var
  // The number of humans --hotseat asks for; 0 without it.
  HotSeatHumans: Integer;
  // The human whose screen opens next (SwitchToNextHuman); nil when the turn does not pass.
  PendingHuman: THuman;
// Adds humans (aPlayerActions.JoinHumanAt) until there are HotSeatHumans. Called after a save
// loads and after a new game starts; a hot-seat save already has its humans.
procedure EnsureHotSeatHumans;
// Whether the next human to end the turn is not the local one, so the screen must pass. Only
// in multiplayer; false when no human holds the day.
function TurnPassesToAnother: Boolean;
// Shows whose turn it is on the open screen, chooses the next human who holds the day
// (PendingHuman) and requests its screen: the star map, the planet or the station it is at.
// Returns false, doing nothing, when the turn does not pass. The caller closes the open screen;
// the human becomes the local one when it has closed (ApplyTurnPass).
function SwitchToNextHuman: Boolean;
// SwitchToNextHuman, then closes Screen, the screen that is open.
procedure PassTurn(Screen: TMessageLoopGI);
// The screen loop calls this between two screens: the human SwitchToNextHuman chose becomes
// the local one, and the film prepared for its star becomes PrimaryFilm.
procedure ApplyTurnPass;
implementation
uses
  SysUtils,
  EC_Struct,
  GI_MessageBox,
  Globals,
  GlobalsV,
  GR_Main,
  aMyFunction,
  aConst,
  aGalaxy,
  aGalaxyStruct,
  aPlanet,
  aPlayer,
  aPlayerActions,
  aSession,
  aStarFilms,
  ThreadCalc,
  fStarMap;

procedure EnsureHotSeatHumans;
var
  Planet: TPlanet;
  Human: THuman;
begin
  // A pass chosen before the load names a human of the old galaxy.
  PendingHuman := nil;
  if (HotSeatHumans <= 1) or (Galaxy = nil) or (LocalPlayer = nil) then
    Exit;
  WaitForTurnCalculation;
  while Session.Humans.Count < HotSeatHumans do
  begin
    Planet := FindJoinPlanet;
    if Planet = nil then
    begin
      AppendLogLineThreadSafe('Hot-seat: no coalition planet left for another human');
      Exit;
    end;
    Human := JoinHumanAt(
        Planet,
        'Human' + WideString(IntToStr(Session.Humans.Count + 1)),
        1 + Session.Humans.Count mod 5
    );
    AppendLogLineThreadSafe(
        Format(
            'Hot-seat: human %d joined at planet %d in star %d',
            [Human.Id, Planet.Id, Planet.CurrentStar.Id]
        )
    );
  end;
end;

function TurnPassesToAnother: Boolean;
var
  Next: THuman;
begin
  if not IsMultiplayer or (PendingHuman <> nil) then
    Exit(False);
  Next := NextHumanToEndTurn;
  Result := (Next <> nil) and (Next <> LocalHuman);
end;

function TurnNotice(Human: THuman): WideString;
begin
  Result := LocalizedColorText('Multiplayer.Turn');
  if Result = '' then
    Result := '<Player>''s turn.';
  ReplaceTextToken(Result, '<Player>', Human.Player.Name, '<color=255,240,100>');
end;

var
  // A timer of the open screen may fire while the notice is shown.
  Switching: Boolean;

function SwitchToNextHuman: Boolean;
var
  Next: THuman;
  P: TPlayer;
begin
  Result := TurnPassesToAnother and not Switching;
  if not Result then
    Exit;
  Switching := True;
  try
    WaitForTurnCalculation;
    Next := NextHumanToEndTurn;
    // The open screen still shows the human who ended the turn.
    ShowMessageBoxGI(
        TMessageLoopGI(RegisteredScreens[Ord(CurrentScreenId)]),
        TurnNotice(Next),
        mbgOK
    );
  finally
    Switching := False;
  end;
  // The switch waits until the open screen has closed (ApplyTurnPass): its close still
  // belongs to the human who ended the turn, as its script hook and its space background do.
  PendingHuman := Next;
  P := Next.Player;
  if P.CurrentPlanet <> nil then
  begin
    if P.CurrentPlanet.OwnerId = Byte(oiUninhabited) then
      RequestedScreenId := screenPlanetNO
    else
      RequestedScreenId := screenPlanet;
  end
  else if P.DockedTo <> nil then
    RequestedScreenId := screenRuinsTalk
  else
  begin
    StarMapScreen.ResumeMode := smrNormal;
    StarMapScreen.SetMapCenterManually(TruncatePointF(P.Position));
    RequestedScreenId := screenStarMap;
  end;
end;

procedure PassTurn(Screen: TMessageLoopGI);
begin
  if SwitchToNextHuman then
    Screen.RequestClose(1);
end;

procedure ApplyTurnPass;
var
  Next: THuman;
  OldStar: TStar;
begin
  Next := PendingHuman;
  PendingHuman := nil;
  if (Next = nil) or (Session.Humans.IndexOf(Next) < 0) or (Next.Player = nil) then
    Exit;
  WaitForTurnCalculation;
  OldStar := LocalHuman.PlayerStar;
  SetLocalHuman(Next);
  // The films follow their stars: the film prepared for the new local star becomes PrimaryFilm.
  ExchangeLocalStarFilm(PrimaryFilm, OldStar, Next.PlayerStar);
  if OldStar <> Next.PlayerStar then
    Galaxy.GenerateSpaceBackground(Next.PlayerStar.BackgroundImage);
end;

end.
