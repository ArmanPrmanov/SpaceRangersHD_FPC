{$EXCESSPRECISION OFF}
unit StarScene;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - Building a star's space scene for the star map, moved verbatim out of
// TStar so that aGalaxy needs no UI controls. A class helper keeps the call syntax and
// the method scoping.
interface
uses
  Classes,
  GI_MessageLoop,
  GI_Panel,
  aGalaxy;
type
  TStarScene = class helper for TStar
    procedure OpenSpaceScene(MapPanel: TPanelGI; Minimap: TObjectGI; Screen: TMessageLoopGI);
    procedure QueueSpaceImageLoads(PendingLoads: TList; Owner: TObjectGI);
    procedure QueueHyperspaceShipImageLoads(PendingLoads: TList; Owner: TObjectGI);
  end;
implementation
uses
  aConst,
  aMyFunction,
  EC_Struct,
  GI_GAI,
  aAsteroid,
  aItem,
  aKling,
  aMissile,
  aPlanet,
  aPlayer,
  aShip,
  SE_Space,
  SE_Gate,
  SE_Hole,
  SE_Ruins,
  SE_Ship2,
  aGalaxyStruct,
  Globals,
  GlobalsV,
  GR_Main;

procedure TStarScene.OpenSpaceScene(MapPanel: TPanelGI; Minimap: TObjectGI; Screen: TMessageLoopGI);
var
  I, J: Integer;
  Planet: TPlanet;
  Asteroid: TAsteroid;
  Hole: THole;
  Satellite: TSputnik;
  Ship: TShip;
  Item: TItem;
  Gate: PJumpGateEntry;
  Missile: TMissile;
begin
  if LocalPlayer <> nil then
  begin
    SpaceProcess.RadarCenter := LocalPlayer.Position;
    SpaceProcess.RadarRange := LocalPlayer.GetRadarRange;
    SpaceProcess.ActionRange := LocalPlayer.GetRadarRange;
    SpaceProcess.ActionColor := CurrentPixelFormat.PackRgbBytes(0, 255, 0);
  end
  else
  begin
    SpaceProcess.RadarCenter := MakePointF(0, 0);
    SpaceProcess.RadarRange := 0;
    SpaceProcess.ActionRange := 0;
    SpaceProcess.ActionColor := 0;
  end;
  SpaceProcess.SystemRadius := ComputeMapDiameter div 2;
  SpaceProcess.PopulateAmbientObjects(ComputeMapDiameter div 2, BackgroundImage, GenerationSeed);
  SpaceProcess.OpenSpace(MapPanel, Screen);
  SpaceProcess.Space.MinimapScale := Minimap.ClientSize.X / ComputeMapDiameter;
  SpaceProcess.Space.AlphaShift := 0;
  if LocalPlayer <> nil then
    if LocalPlayer.IsHealthEffectActive(1) then
      SpaceProcess.Space.AlphaShift := 2;
  SpaceProcess.BindMinimap(Minimap);
  Graphic.AttachToSpace(SpaceProcess.Space);
  for I := 0 to Planets.Count - 1 do
  begin
    Planet := TPlanet(Planets[I]);
    Planet.Graphic.Civilized := Planet.OwnerId <> Byte(oiUninhabited);
    Planet.Graphic.SetMinimapOwner(Planet.OwnerId);
    if Planet.CustomFaction <> '' then
    begin
      J := GetCustomFactionPlanetIconNumber(Planet.CustomFaction);
      if J >= 0 then
        Planet.Graphic.SetMinimapOwner(J + 1 + 7);
    end;
    Planet.Graphic.SetSurfaceAnimationMask(Planet.GetSurfaceAnimationMask);
    Planet.Graphic.AttachToSpace(SpaceProcess.Space);
    if SputnikShow then
      for J := 0 to Planet.Satellites.Count - 1 do
      begin
        Satellite := TSputnik(Planet.Satellites[J]);
        Satellite.Graphic.OrbitCenter := Planet.GetPosition;
        Satellite.Graphic.AttachToSpace(SpaceProcess.Space);
      end;
  end;
  for I := 0 to Asteroids.Count - 1 do
  begin
    Asteroid := TAsteroid(Asteroids[I]);
    Asteroid.GraphObject.AttachToSpace(SpaceProcess.Space);
  end;
  for I := 0 to Ships.Count - 1 do
  begin
    Ship := TShip(Ships[I]);
    if Ship.InNormalSpace then
    begin
      Ship.Graphic.SetAlpha(255);
      if Ship.Graphic is TShip2SE then
      begin
        with TShip2SE(Ship.Graphic) do
          if (ShipTail = 2) or ((ShipTail = 1) and (LocalPlayer = Ship)) then
            SetTailMode(1)
          else
            SetTailMode(0);
      end
      else if (Ship.Graphic is TRuinsSE) and (Ship.Graphic as TRuinsSE).HasTransitionImages then
        (Ship.Graphic as TRuinsSE).SetState(1);
      Ship.Graphic.AttachToSpace(SpaceProcess.Space);
      if Ship.InterceptorGraphic <> nil then
      begin
        Ship.InterceptorGraphic.SetAlpha(255);
        Ship.InterceptorGraphic.AttachToSpace(SpaceProcess.Space);
      end;
    end;
  end;
  for I := 0 to Items.Count - 1 do
  begin
    Item := TItem(Items[I]);
    Item.GetGraphObject.AttachToSpace(SpaceProcess.Space);
  end;
  for I := 0 to Galaxy.JumpGates.Count - 1 do
  begin
    Gate := Galaxy.JumpGates[I];
    TGateSE(Gate.Gate).SetState(2);
    Gate.Gate.AttachToSpace(SpaceProcess.Space);
  end;
  for I := 0 to Galaxy.Holes.Count - 1 do
  begin
    Hole := THole(Galaxy.Holes[I]);
    if Hole.Star1 = Self then
    begin
      Hole.Graphic.SetPosition(Hole.Position1);
      THoleSE(Hole.Graphic).SetState(0);
      Hole.Graphic.AttachToSpace(SpaceProcess.Space);
    end
    else if Hole.Star2 = Self then
    begin
      Hole.Graphic.SetPosition(Hole.Position2);
      THoleSE(Hole.Graphic).SetState(0);
      Hole.Graphic.AttachToSpace(SpaceProcess.Space);
    end;
  end;
  for I := 0 to Missiles.Count - 1 do
  begin
    Missile := TMissile(Missiles[I]);
    Missile.GetGraphObject.AttachToSpace(SpaceProcess.Space);
  end;
end;
procedure TStarScene.QueueSpaceImageLoads(PendingLoads: TList; Owner: TObjectGI);
var
  Planet: TPlanet;
  Ship: TShip;
  Hole: THole;
  Item: TItem;
  I, J: Integer;
  Satellite: TSputnik;
  Asteroid: TAsteroid;
begin
  Graphic.QueueImageLoad(PendingLoads, Owner);
  if (TerronShip <> nil) and (TerronShip.CurrentStar = Self) and AnimStar then
  begin
    with TgaiGI.Create(Owner) do
    begin
      SetImagePath('Bm.Star.Terron_Transform_a');
      QueueImageLoad(PendingLoads);
      Free;
    end;
    with TgaiGI.Create(Owner) do
    begin
      SetImagePath('Bm.Star.TerronAfter_a');
      QueueImageLoad(PendingLoads);
      Free;
    end;
  end;
  for I := 1 to Planets.Count do
  begin
    Planet := TPlanet(Planets[I - 1]);
    Planet.Graphic.QueueImageLoad(PendingLoads, Owner);
    if SputnikShow then
      for J := 0 to Planet.Satellites.Count - 1 do
      begin
        Satellite := TSputnik(Planet.Satellites[J]);
        Satellite.Graphic.QueueImageLoad(PendingLoads, Owner);
      end;
  end;
  for I := 1 to Ships.Count do
  begin
    Ship := TShip(Ships[I - 1]);
    Ship.Graphic.QueueImageLoad(PendingLoads, Owner);
  end;
  for I := 1 to Items.Count do
  begin
    Item := TItem(Items[I - 1]);
    Item.GetGraphObject.QueueImageLoad(PendingLoads, Owner);
  end;
  for I := 0 to Asteroids.Count - 1 do
  begin
    Asteroid := TAsteroid(Asteroids[I]);
    Asteroid.GraphObject.QueueImageLoad(PendingLoads, Owner);
  end;
  for I := 0 to Galaxy.Holes.Count - 1 do
  begin
    Hole := THole(Galaxy.Holes[I]);
    if (Hole.Star1 = Self) or (Hole.Star2 = Self) then
      Hole.Graphic.QueueImageLoad(PendingLoads, Owner);
  end;
end;
procedure TStarScene.QueueHyperspaceShipImageLoads(PendingLoads: TList; Owner: TObjectGI);
var
  Ship: TShip;
  I: Integer;
begin
  for I := 1 to Ships.Count do
  begin
    Ship := TShip(Ships[I - 1]);
    if Ship.InHyperspace then
      Ship.Graphic.QueueImageLoad(PendingLoads, Owner);
  end;
end;
end.
