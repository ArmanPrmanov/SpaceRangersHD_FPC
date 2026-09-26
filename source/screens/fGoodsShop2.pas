{$EXCESSPRECISION OFF}
unit fGoodsShop2;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  Types,
  aGalaxyStruct,
  GR_Sound,
  EC_BlockPar,
  GI_MessageLoop,
  fPanelLoad,
  fPanelMain,
  fPanelPlanet,
  fPanelRuins;
type
  TfGoodsShop2 = class;
  TfGoodsShop2 = class(TMessageLoopGIWithMainPanel)
    PlanetPanel: TfPanelPlanet;
    StationPanel: TfPanelRuins;
    LoadPanel: TfPanelLoad;
    DraggedGoodsIndex: Integer;
    NameFaceHeight: Integer;
    FaceCaptionHeight: Integer;
    FlagEC: Boolean;
    GapED: array[0..2] of Byte;
    PartnerCargoLimit: Integer;
    PartnerMoneyLimit: Integer;
    MoneyWarningActive: Boolean;
    Gap179: array[0..2] of Byte;
    MoneyWarningTicks: Integer;
    MoneyWarningTimer: PCallbackTimerGI;
    CargoWarningActive: Boolean;
    Gap185: array[0..2] of Byte;
    CargoWarningTicks: Integer;
    CargoWarningTimer: PCallbackTimerGI;
    AmbientSound: TSoundBufferControl;
    procedure OnOpen; override;
    procedure OnClose; override;
    procedure ProcessCallbackTimers; override;
    procedure SelectMusic; override;
    procedure InitializeLayout; override;
    procedure UpdateActionCursor(CanTake: Boolean); override;
    procedure ExecuteUiCode(Block: TBlockParEC; Key: Cardinal); override;
    constructor Create;
    destructor Destroy; override;
    procedure RefreshGoodsDisplay;
    procedure GoodsMouseUp(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
    procedure GoodsRightMouseDown(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
    procedure GoodsMouseMove(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
    procedure GoodsMouseEnter(Sender: TObjectGI);
    procedure GoodsMouseLeave(Sender: TObjectGI);
    function GetMaximumTradeCount(Index: Integer; IgnoreCargoSpace: Boolean): Integer;
    function GetAvailableGoodsCount(Index: Integer): Integer;
    function BuildPriceText(Location: TObject): WideString;
    procedure SavePricesClicked(Sender: TObjectGI);
    procedure EndTurnClicked(Sender: TObjectGI);
    procedure GalaxyClicked(Sender: TObjectGI);
    procedure QuestClicked(Sender: TObjectGI);
    procedure MenuClicked(Sender: TObjectGI);
    procedure ShipClicked(Sender: TObjectGI);
    procedure FinishModalTrade;
    procedure CaptureMerchantBackground(Sender: TObjectGI);
    procedure MerchantAnimationComplete(Sender: TObjectGI);
    procedure CloseClicked(Sender: TObjectGI);
    procedure RefreshMoneyWarning;
    procedure FlashMoneyWarning;
    procedure MoneyWarningTick(Timer: PCallbackTimerGI; UserData: PtrInt);
    procedure RefreshCargoWarning;
    procedure FlashCargoWarning;
    procedure CargoWarningTick(Timer: PCallbackTimerGI; UserData: PtrInt);
    procedure MainPanelKeyDown(Sender: TObjectGI; Key: Cardinal);
    procedure ShowControlHelp(Sender: TObjectGI; Visible: Boolean);
    procedure ShowHelpText(Value: WideString; Visible: Boolean);
  end;
const
  ShopGoodsOrder: TGoodsTextOrder = (0, 1, 5, 4, 3, 2, 6, 7);
function RunGoodsShop(ParentLoop: TMessageLoopGI): Boolean;
procedure LinkRecoveredTypes;
implementation
uses
  aPlayerActions,
  aShopActions,
  aHuman,
  GI_GI,
  ThreadCalc,
  aCalc,
  aItem,
  aScript,
  fEquipmentShop,
  aShopStock,
  GI_Panel,
  SE_Ruins,
  aRanger,
  GI_MessageBox,
  fCount2,
  EC_Str,
  EC_Mem,
  GI_GAI,
  fRuinsTalk,
  Classes,
  Math,
  Windows,
  GI_Main,
  GI_Image,
  GI_GraphButton,
  GI_GraphBuf,
  GI_Label,
  GR_GraphBuf,
  GR_Music,
  fStarMap,
  fShip2,
  Globals,
  GlobalsV,
  GR_Main,
  SysUtils,
  aGalaxy,
  aConst,
  aMyFunction,
  aPlanet,
  aPlayer,
  aRuins,
  aShip;
var
  OutOfStockColor: WideString; // @addr $88B100 Native style-derived out-of-stock price markup.

constructor TfGoodsShop2.Create;
begin
  inherited Create;
  PlanetPanel := TfPanelPlanet.Create;
  StationPanel := TfPanelRuins.Create;
  LoadPanel := TfPanelLoad.Create;
  AmbientSound := TSoundBufferControl.Create;
  AmbientSound.Configure('Sound.GoodsLoop', 0, True);
end;

destructor TfGoodsShop2.Destroy;
begin
  if PlanetPanel <> nil then
  begin
    PlanetPanel.Free;
    PlanetPanel := nil;
  end;
  if StationPanel <> nil then
  begin
    StationPanel.Free;
    StationPanel := nil;
  end;
  if LoadPanel <> nil then
  begin
    LoadPanel.Free;
    LoadPanel := nil;
  end;
  AmbientSound.Free;
  inherited Destroy;
end;

procedure TfGoodsShop2.InitializeLayout;
begin
  inherited InitializeLayout;
  MainPanel.InitializeLayout(Self);
  PlanetPanel.InitializeLayout(Self);
  StationPanel.InitializeLayout(Self);
  LoadPanel.InitializeLayout(Self);
  SetHelpCallback(ShowControlHelp);
  AppendLogTextThreadSafe('fGoodsShop2... ');
  ViewportRect := Classes.Rect(0, 0, GameScreenWidth, GameScreenHeight);
  with GetByName('MainPanel') do
  begin
    SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
    FindByNameRecursive('BGBuf').SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
    FindByNameRecursive('BGCity2').SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
    FindByNameRecursive('BGCity').SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
    with FindByNameRecursive('ADD_WarningSpace') do
      SetPosition(
          Classes.Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight)
      );
    with FindByNameRecursive('ADD_WarningMoney') do
      SetPosition(
          Classes.Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight)
      );
    with FindByNameRecursive('ADD_Space') do
      SetPosition(
          Classes.Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight)
      );
    with FindByNameRecursive('ADD_Money') do
      SetPosition(
          Classes.Point(LocalPosition.X + ExtraScreenWidth, LocalPosition.Y + ExtraScreenHeight)
      );
    with FindByNameRecursive('GS_Help') do
      SetPosition(Classes.Point(LocalPosition.X, LocalPosition.Y + ExtraScreenHeight));
    with FindByNameRecursive('GoodsPanel') do
      SetPosition(
          Classes.Point(
              LocalPosition.X + ExtraScreenWidth div 2,
              LocalPosition.Y + ExtraScreenHeight div 2
          )
      );
    FindByNameRecursive('BGShrLight').SetSize(Classes.Point(GameScreenWidth, GameScreenHeight));
  end;
  AppendLogLineThreadSafe('ok');
  (GetByName('PM_EndTurn') as TGraphButtonGI).UpCallback := EndTurnClicked;
  (GetByName('PM_Ship') as TGraphButtonGI).UpCallback := ShipClicked;
  (GetByName('PM_Gal') as TGraphButtonGI).UpCallback := GalaxyClicked;
  (GetByName('PM_Quest') as TGraphButtonGI).UpCallback := QuestClicked;
  (GetByName('PM_Logo') as TGraphButtonGI).UpCallback := MenuClicked;
  GetByName('MainPanel').KeyDownCallback := MainPanelKeyDown;
  GetByName('MainPanel').MouseMoveCallback := GoodsMouseMove;
  GetByName('MainPanel').LeftButtonUpCallback := GoodsMouseUp;
  GetByName('MainPanel').RightButtonDownCallback := GoodsRightMouseDown;
  (GetByName('UserMsgAdd') as TGraphButtonGI).UpCallback := SavePricesClicked;
  NameFaceHeight := (GetByName('NameFace') as TLabelGI).ClientSize.Y;
  FaceCaptionHeight :=
      (GetByName('CharFace') as TLabelGI).LocalPosition.Y
          + (GetByName('CharFace') as TLabelGI).ClientSize.Y
          - (GetByName('NameFace') as TLabelGI).LocalPosition.Y;
  OutOfStockColor := GetStyleColorTagGI('GoodsShop.GoodsColorOutOfStock', 127, 127, 127);
end;

procedure TfGoodsShop2.OnOpen;
var
  I: Integer;
  BackgroundPath: WideString;
  UnusedNativeLocal: array[0..3] of Byte; { Unreferenced native storage; original type is unknown. }
begin
  if not FlagEC then
    LoadPanel.OnOpen;
  if not MusicInPlanetEnabled then
    MusicManager.RequestFadeOut;
  if LocalPlayer.IsOnPlanet or LocalPlayer.IsDockedToShip then
  begin
    MainPanel.Show;
    MainPanel.OnOpen;
  end
  else
    MainPanel.Hide;
  for I := 0 to 17 do
    if (I <> 8) and (I <> 9) then
    begin
      with GetByName('TovCnt' + IntToStr(I)) as TLabelGI do
      begin
        if FontDialog = 0 then
          SetFontName(NormalFontName)
        else if FontDialog = 1 then
          SetFontName(SmoothBigFontName)
        else if FontDialog = 2 then
          SetFontName(SmoothHugeFontName)
        else if FontDialog >= 3 then
          SetFontName(SmoothIntroFontName);
      end;
      with GetByName('TovPrice' + IntToStr(I)) as TLabelGI do
      begin
        if FontDialog = 0 then
          SetFontName(NormalFontName)
        else if FontDialog = 1 then
          SetFontName(SmoothBigFontName)
        else if FontDialog = 2 then
          SetFontName(SmoothHugeFontName)
        else if FontDialog >= 3 then
          SetFontName(SmoothIntroFontName);
      end;
    end;
  GetByName('GS_Help').SetActive(False);
  (GetByName('UserMsgAdd') as TGraphButtonGI).SetDisabled(False);
  with GetByName('ButFormClose') as TGraphButtonGI do
    if LocalPlayer.IsOnPlanet then
      UpCallback := PlanetPanel.PlanetClicked
    else if LocalPlayer.IsDockedToShip then
      UpCallback := StationPanel.ServicesClicked
    else
      UpCallback := CloseClicked;
  DraggedGoodsIndex := -1;
  (GetByName('NameFace') as TLabelGI)
      .SetSize(Classes.Point((GetByName('NameFace') as TLabelGI).ClientSize.X, NameFaceHeight));
  GetByName('GraphBufFace').SetActive(False);
  GetByName('CloseLine').SetActive(False);
  if LocalPlayer.IsOnPlanet then
  begin
    (GetByName('NameFace') as TLabelGI).SetText(LocalPlayer.CurrentPlanet.GetFullName(#13#10));
    if LocalPlayer.CurrentPlanet.IsMainPiratePlanet then
      (GetByName('CharFace') as TLabelGI).SetText('')
    else
      (GetByName('CharFace') as TLabelGI)
          .SetText(
              PlanetEconomyInfo[Ord(LocalPlayer.CurrentPlanet.Economy)].ShortDisplayName
                  + #13#10
                  + PlanetGovernmentMarket[Ord(LocalPlayer.CurrentPlanet.Government)].DisplayName);
    (GetByName('ImageFace') as TImageGI)
        .SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + 'PlanetL');
    with GetByName('GraphBufFace') as TGraphBufGI do
    begin
      SetActive(True);
      SourceHasPerPixelAlpha := True;
      LocalPlayer.CurrentPlanet.Graphic.RenderToBuffer(Self, GraphBuf, False);
      GraphBuf.RescaleBilinearRgba(ClientSize.X, ClientSize.Y);
    end;
  end
  else if LocalPlayer.IsDockedToShip then
  begin
    (GetByName('NameFace') as TLabelGI).SetText(LocalPlayer.DockedTo.GetFullName(#13#10));
    (GetByName('CharFace') as TLabelGI).SetText('');
    GetByName('CloseLine').SetActive(True);
    (GetByName('NameFace') as TLabelGI)
        .SetSize(
            Classes.Point((GetByName('NameFace') as TLabelGI).ClientSize.X, FaceCaptionHeight));
    (GetByName('ImageFace') as TImageGI)
        .SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + 'AllL');
    with GetByName('GraphBufFace') as TGraphBufGI do
    begin
      SetActive(True);
      SourceHasPerPixelAlpha := True;
      if LocalPlayer.DockedTo.Graphic is TRuinsSE then
        LoadGiByPathIntoGraphBuf(
            ExtractDelimitedPartW((LocalPlayer.DockedTo.Graphic as TRuinsSE).StaticImagePath, 1, ','),
            GraphBuf
        )
      else
        LoadGiByPathIntoGraphBuf(
            ExtractDelimitedPartW(LocalPlayer.DockedTo.GetShipPortraitImagePath, 1, ','),
            GraphBuf
        );
      if Cardinal(GraphBuf.Width) >= Cardinal(GraphBuf.Height) then
        GraphBuf.RescaleRgba(
            ClientSize.X,
            Round(ClientSize.X / Cardinal(GraphBuf.Width) * Cardinal(GraphBuf.Height)),
            5
        )
      else
        GraphBuf.RescaleRgba(
            Round(ClientSize.Y / Cardinal(GraphBuf.Height) * Cardinal(GraphBuf.Width)),
            ClientSize.Y,
            5
        );
    end;
  end
  else if LocalPlayer.InNormalSpace then
  begin
    if LocalHuman.TalkShip is TRanger then
    begin
      (GetByName('NameFace') as TLabelGI).SetText(LocalHuman.TalkShip.GetFullName(#13#10));
      (GetByName('CharFace') as TLabelGI).SetText((LocalHuman.TalkShip as TRanger).GetCharacterName);
    end
    else
    begin
      (GetByName('NameFace') as TLabelGI).SetText(LocalHuman.TalkShip.GetFullName(#13#10));
      (GetByName('CharFace') as TLabelGI).SetText('');
      GetByName('CloseLine').SetActive(True);
      (GetByName('NameFace') as TLabelGI)
          .SetSize(
              Classes.Point((GetByName('NameFace') as TLabelGI).ClientSize.X, FaceCaptionHeight));
    end;
    (GetByName('ImageFace') as TImageGI)
        .SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + 'AllL');
    with GetByName('GraphBufFace') as TGraphBufGI do
    begin
      SetActive(True);
      SourceHasPerPixelAlpha := True;
      if LocalHuman.TalkShip.Graphic is TRuinsSE then
        LoadGiByPathIntoGraphBuf(
            ExtractDelimitedPartW((LocalHuman.TalkShip.Graphic as TRuinsSE).StaticImagePath, 1, ','),
            GraphBuf
        )
      else
        LoadGiByPathIntoGraphBuf(
            ExtractDelimitedPartW(LocalHuman.TalkShip.GetShipPortraitImagePath, 1, ','),
            GraphBuf
        );
      if Cardinal(GraphBuf.Width) >= Cardinal(GraphBuf.Height) then
        GraphBuf.RescaleRgba(
            ClientSize.X,
            Round(ClientSize.X / Cardinal(GraphBuf.Width) * Cardinal(GraphBuf.Height)),
            5
        )
      else
        GraphBuf.RescaleRgba(
            Round(ClientSize.Y / Cardinal(GraphBuf.Height) * Cardinal(GraphBuf.Width)),
            ClientSize.Y,
            5
        );
    end;
  end;
  if FlagEC then
  begin
    with GetByName('FaceA') as TgaiGI do
    begin
      SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
      RestartPlayback;
    end;
    with GetByName('CaptainA') as TgaiGI do
      RestartPlayback;
  end
  else
  begin
    if LocalPlayer.IsOnPlanet then
    begin
      with GetByName('FaceI') as TImageGI do
      begin
        SetImagePath('GI,Bm.Captain.' + GiResourceSuffix + 'ShopBot1i');
        SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
        SetImageKindX(ikxCenter);
        SetImageKindY(ikyCenter);
        SetActive(True);
      end;
      with GetByName('FaceA') as TgaiGI do
      begin
        FirstFrameOnly := not AnimCaptain;
        SetImagePath('Bm.Captain.' + GiResourceSuffix + 'ShopBot1a');
        SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
        SequenceIndex := 0;
        UpdateAutoGeometry;
        SetSequenceFrame(RandomIntRange(0, SequenceFrameCount - 1));
        SetImageKindX(ikxCenter);
        SetImageKindY(ikyCenter);
        SetActive(True);
        RestartPlayback;
        UserValue := 1;
        CycleCompleteCallback := MerchantAnimationComplete;
      end;
    end
    else if LocalPlayer.IsDockedToShip then
    begin
      with GetByName('FaceI') as TImageGI do
      begin
        SetImagePath('GI,Bm.Captain.' + GiResourceSuffix + 'ShopBot1i');
        SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
        SetImageKindX(ikxCenter);
        SetImageKindY(ikyCenter);
        SetActive(True);
      end;
      with GetByName('FaceA') as TgaiGI do
      begin
        FirstFrameOnly := not AnimCaptain;
        SetImagePath('Bm.Captain.' + GiResourceSuffix + 'ShopBot1a');
        SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
        SequenceIndex := 0;
        UpdateAutoGeometry;
        SetSequenceFrame(RandomIntRange(0, SequenceFrameCount - 1));
        SetImageKindX(ikxCenter);
        SetImageKindY(ikyCenter);
        SetActive(True);
        RestartPlayback;
        UserValue := 1;
        CycleCompleteCallback := MerchantAnimationComplete;
      end;
    end
    else if LocalPlayer.InNormalSpace then
    begin
      with GetByName('FaceI') as TImageGI do
      begin
        SetImagePath('GI,' + LocalHuman.TalkShip.GetCaptainPortraitResourceBase + 'i');
        SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
        SetImageKindX(ikxCenter);
        SetImageKindY(ikyCenter);
        SetActive(True);
      end;
      with GetByName('FaceA') as TgaiGI do
      begin
        FirstFrameOnly := not AnimCaptain;
        SetImagePath(LocalHuman.TalkShip.GetCaptainPortraitResourceBase + 'a');
        SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
        SequenceIndex := 0;
        UpdateAutoGeometry;
        SetSequenceFrame(RandomIntRange(0, SequenceFrameCount - 1));
        SetImageKindX(ikxCenter);
        SetImageKindY(ikyCenter);
        SetActive(True);
        RestartPlayback;
        CycleCompleteCallback := nil;
      end;
    end;
    with GetByName('FaceA') as TgaiGI do
      FrameAdvancedCallback := CaptureMerchantBackground;
    GetByName('FaceGB').SetActive(False);
    with GetByName('CaptainI') as TImageGI do
    begin
      SetImagePath('GI,' + LocalPlayer.GetCaptainPortraitResourceBase + 'i');
      SetImageKindX(ikxCenter);
      SetImageKindY(ikyCenter);
      SetActive(True);
    end;
    with GetByName('CaptainA') as TgaiGI do
    begin
      FirstFrameOnly := not AnimCaptain;
      SetImagePath(LocalPlayer.GetCaptainPortraitResourceBase + 'a');
      SequenceIndex := 0;
      UpdateAutoGeometry;
      SetImageKindX(ikxCenter);
      SetImageKindY(ikyCenter);
      SetActive(True);
      RestartPlayback;
    end;
    (GetByName('NameCaptain') as TLabelGI).SetText(LocalPlayer.GetFullName(#13#10));
    (GetByName('CharCaptain') as TLabelGI).SetText(LocalPlayer.GetCharacterName);
  end;
  (GetByName('ImageCaptain') as TImageGI)
      .SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + 'AllR');
  with GetByName('GraphBufCaptain') as TGraphBufGI do
  begin
    SetActive(True);
    SourceHasPerPixelAlpha := True;
    if LocalPlayer.Graphic is TRuinsSE then
      LoadGiByPathIntoGraphBuf(
          ExtractDelimitedPartW((LocalPlayer.Graphic as TRuinsSE).StaticImagePath, 1, ','),
          GraphBuf
      )
    else
      LoadGiByPathIntoGraphBuf(
          ExtractDelimitedPartW(LocalPlayer.GetShipPortraitImagePath, 1, ','),
          GraphBuf
      );
    if Cardinal(GraphBuf.Width) >= Cardinal(GraphBuf.Height) then
      GraphBuf.RescaleRgba(
          ClientSize.X,
          Round(ClientSize.X / Cardinal(GraphBuf.Width) * Cardinal(GraphBuf.Height)),
          5
      )
    else
      GraphBuf.RescaleRgba(
          Round(ClientSize.Y / Cardinal(GraphBuf.Height) * Cardinal(GraphBuf.Width)),
          ClientSize.Y,
          5
      );
  end;
  if LocalPlayer.IsOnPlanet then
  begin
    PlanetPanel.OnOpen;
    PlanetPanel.Show;
    StationPanel.Hide;
  end
  else if LocalPlayer.IsDockedToShip then
  begin
    PlanetPanel.Hide;
    StationPanel.OnOpen;
    StationPanel.Show;
  end
  else
  begin
    PlanetPanel.Hide;
    StationPanel.Hide;
  end;
  with GetByName('BGCity2') as TImageGI do
  begin
    SetActive(LocalPlayer.IsDockedToShip and (LocalPlayer.DockedTo.TypeId = Byte(rstMilitaryBase)));
    if Active then
    begin
      SetImagePath('GAI,' + LocalPlayer.CurrentStar.GetBackgroundImagePath(I));
      GaiImageControl.LoadFrameSequenceFromText('[50,0-0]');
      SetImageKindX(ikxCenter);
      SetImageKindY(ikyCenter);
    end;
  end;
  with GetByName('BGCity') as TImageGI do
    if LocalPlayer.IsOnPlanet then
    begin
      SetActive(True);
      (FindByNameRecursive('BGCity') as TImageGI)
          .SetImagePath(LocalPlayer.CurrentPlanet.GetGovernmentBackgroundGraph);
    end
    else if LocalPlayer.IsDockedToShip then
    begin
      SetActive(True);
      if LocalPlayer.DockedTo.TypeNameOverrideKey <> '' then
      begin
        BackgroundPath :=
            'Bm.FormRuins.' + GiResourceSuffix + LocalPlayer.DockedTo.TypeNameOverrideKey + 'bg';
        if CacheDataRoot.FileExistsByPath(BackgroundPath) then
          SetImagePath('GI,' + BackgroundPath)
        else
          SetImagePath(
              'GI,Bm.FormRuins.'
                  + GiResourceSuffix
                  + ShipTypeNames[LocalPlayer.DockedTo.TypeId].Name
                  + 'bg'
          );
      end
      else
        SetImagePath(
            'GI,Bm.FormRuins.'
                + GiResourceSuffix
                + ShipTypeNames[LocalPlayer.DockedTo.TypeId].Name
                + 'bg'
        );
    end
    else
      SetActive(False);
  with GetByName('BGBuf') as TGraphBufGI do
    if LocalPlayer.InNormalSpace then
    begin
      if AuxRenderBuffer.GetPixels = nil then
        CaptureScreenBackground(True, 0);
      BindExternalGraphBuf(AuxRenderBuffer);
      SetActive(True);
    end
    else
      SetActive(False);
  GetByName('BGShrLight').SetActive(LocalPlayer.InNormalSpace and not BackgroundShade);
  MainPanel.RebuildMessageButtons(False);
  RefreshGoodsDisplay;
  CaptureMerchantBackground(nil);
  MoneyWarningActive := False;
  CargoWarningActive := False;
  RefreshMoneyWarning;
  RefreshCargoWarning;
  FlagEC := False;
  AmbientSound.SetVolume(1);
  if LocalPlayer <> nil then
    RunScriptItemsAct(LocalPlayer, satOnEnteringForm, nil, nil, 0);
  if not LocalPlayer.InNormalSpace then
    aCalc.WaitForTurnCalculationUI;
end;

procedure TfGoodsShop2.OnClose;
begin
  if LocalPlayer <> nil then
    if not LocalPlayer.InNormalSpace then
      aCalc.WaitForTurnCalculationUI;
  if LocalPlayer <> nil then
    RunScriptItemsAct(LocalPlayer, satOnLeavingForm, nil, nil, 0);
  LoadPanel.OnClose;
  if MoneyWarningTimer <> nil then
  begin
    CancelCallbackTimer(MoneyWarningTimer);
    MoneyWarningTimer := nil;
  end;
  if CargoWarningTimer <> nil then
  begin
    CancelCallbackTimer(CargoWarningTimer);
    CargoWarningTimer := nil;
  end;
  if LocalPlayer <> nil then
    if LocalPlayer.IsOnPlanet or LocalPlayer.IsDockedToShip then
      MainPanel.OnClose;
  (GetByName('GraphBufFace') as TGraphBufGI).GraphBuf.Clear;
  if (LocalPlayer <> nil) and LocalPlayer.IsOnPlanet then
    PlanetPanel.OnClose
  else if LocalPlayer <> nil then
    if LocalPlayer.IsDockedToShip then
      StationPanel.OnClose;
  if not FlagEC then
    AmbientSound.SetVolume(0);
end;

procedure TfGoodsShop2.RefreshGoodsDisplay;
var
  Good: Byte;
  I, J, IconCount, SellPrice, OldCost: Integer;
  Panel: TPanelGI;
  Image: TImageGI;
  ImageName, Color: WideString;
  Location: TObject;
begin
  if LocalPlayer.InNormalSpace then
  begin
    // The prices are computed again from the partner's cargo, so a trade command can compute
    // them too; the state hash leaves them out.
    RefreshTradeRows(LocalHuman, LocalHuman.TalkShip);
    PartnerCargoLimit := LocalHuman.TalkShip.GetCargoFreeSpace - LocalHuman.TalkShip.GetDesiredCargoFreeSpace;
    PartnerMoneyLimit := LocalHuman.TalkShip.Money;
  end;
  with GetByName('DownLeft') do
    SetActive((DraggedGoodsIndex >= 10) and (DraggedGoodsIndex < 20));
  with GetByName('DownRight') do
    SetActive((DraggedGoodsIndex >= 0) and (DraggedGoodsIndex < 10));
  for I := 0 to 7 do
  begin
    Good := ShopGoodsOrder[I];
    with GetByName('Tov' + IntToStr(I)) as TGraphButtonGI do
    begin
      MouseEnterCallback := GoodsMouseEnter;
      MouseLeaveCallback := GoodsMouseLeave;
      SetDisabled(
          (((DraggedGoodsIndex >= 10) and (DraggedGoodsIndex < 20))
                  or (LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[I]).Count <= 0))
              and ((DraggedGoodsIndex < 10)
                  or (DraggedGoodsIndex >= 20)
                  or (DraggedGoodsIndex mod 10 <> I))
      );
    end;
    with GetByName('Tov' + IntToStr(I + 10)) as TGraphButtonGI do
    begin
      MouseEnterCallback := GoodsMouseEnter;
      MouseLeaveCallback := GoodsMouseLeave;
      SetDisabled(
          (((DraggedGoodsIndex >= 0) and (DraggedGoodsIndex < 10))
                  or (LocalPlayer.CargoGoods[ShopGoodsOrder[I]].Count <= 0))
              and ((DraggedGoodsIndex < 0)
                  or (DraggedGoodsIndex >= 10)
                  or (DraggedGoodsIndex mod 10 <> I))
      );
    end;
    GetByName('TovPermit' + IntToStr(I + 1))
        .SetActive(LocalPlayer.IsCargoGoodIllegalOnCurrentPlanet(ShopGoodsOrder[I]));
    GetByName('TovPermit' + IntToStr(I + 10 + 1))
        .SetActive(GetByName('TovPermit' + IntToStr(I + 1)).Active);
    Panel := GetByName('TovCool' + IntToStr(I + 1)) as TPanelGI;
    Panel.Invalidate;
    Panel.FreeOwnedChildren;
    if LocalPlayer.GetLocationGoodsEntry(Good).Count <= 0 then
      IconCount := 0
    else
      IconCount :=
          Round(
              RemapClamped(
                  Integer(
                          Galaxy.GetGoodsPricePercent(
                              Good,
                              LocalPlayer.ShopGoodsPurchasePrice(Good, nil)
                          ))
                      and $7F,
                  0,
                  30,
                  3,
                  0
              )
          );
    ImageName := 'Good';
    for J := 0 to IconCount - 1 do
    begin
      Image := TImageGI.Create(Panel);
      Image.SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + ImageName);
      Image.SetSize(Image.GetContentSize);
      Image.SetPosition(Classes.Point(Panel.ClientSize.X - (Image.ClientSize.X + 1) * (J + 1), 0));
    end;
    Panel := GetByName('TovCool' + IntToStr(I + 10 + 1)) as TPanelGI;
    Panel.Invalidate;
    Panel.FreeOwnedChildren;
    OldCost := Round(LocalPlayer.GetAverageCargoCost(Good));
    SellPrice := LocalPlayer.ShopGoodsSellPrice(Good, nil);
    if LocalPlayer.CargoGoods[Good].Count > 0 then
    begin
      if SellPrice > OldCost then
        IconCount := 1
      else
        IconCount := 0;
    end
    else
      IconCount := 0;
    ImageName := 'Good';
    for J := 0 to IconCount - 1 do
    begin
      Image := TImageGI.Create(Panel);
      Image.SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + ImageName);
      Image.SetSize(Image.GetContentSize);
      Image.SetPosition(Classes.Point(Panel.ClientSize.X - (Image.ClientSize.X + 1) * (J + 1), 0));
    end;
  end;
  for I := 0 to 7 do
  begin
    Good := ShopGoodsOrder[I];
    Panel := GetByName('TovImgCnt' + IntToStr(I)) as TPanelGI;
    Panel.FreeOwnedChildren;
    Panel.Invalidate;
    IconCount :=
        Round(LocalPlayer.GetLocationGoodsEntry(Good).Count / GoodsMarket[Good].BaseStock * 6);
    if (IconCount <= 0) and (LocalPlayer.GetLocationGoodsEntry(Good).Count >= 1) then
      IconCount := 1
    else if IconCount > 6 then
      IconCount := 6;
    for J := 0 to IconCount - 1 do
    begin
      Image := TImageGI.Create(Panel);
      Image.SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + 'Goods' + IntToStr(I + 1));
      if I in [2, 4, 5, 6] then
        Image.SetPosition(Classes.Point(J * GiScalePixels(12), 0))
      else
        Image.SetPosition(Classes.Point(J * GiScalePixels(11), 0));
      Image.SetDepth(J);
      Image.SetSize(Image.GetContentSize);
    end;
    Color := '';
    if LocalPlayer.GetLocationGoodsEntry(Good).Count < 0 then
      RaiseWideMessage('Player.ShopGoods(it).Cnt<0')
    else if LocalPlayer.GetLocationGoodsEntry(Good).Count = 0 then
      Color := OutOfStockColor;
    { Native writes this sell-price label once with the market color, then again with the cargo color below. }
    (GetByName('TovPrice' + IntToStr(I + 10)) as TLabelGI)
        .SetText(WrapTextInColor(IntToStr(LocalPlayer.ShopGoodsSellPrice(Good, nil)), Color));
    (GetByName('TovCnt' + IntToStr(I)) as TLabelGI)
        .SetText(WrapTextInColor(IntToStr(LocalPlayer.GetLocationGoodsEntry(Good).Count), Color));
    (GetByName('TovPrice' + IntToStr(I)) as TLabelGI)
        .SetText(WrapTextInColor(IntToStr(LocalPlayer.ShopGoodsPurchasePrice(Good, nil)), Color));
    Panel := GetByName('TovImgCnt' + IntToStr(I + 10)) as TPanelGI;
    Panel.FreeOwnedChildren;
    IconCount := Round(LocalPlayer.CargoGoods[Good].Count / GoodsMarket[Good].BaseStock * 6);
    if (IconCount <= 0) and (LocalPlayer.CargoGoods[Good].Count >= 1) then
      IconCount := 1
    else if IconCount > 6 then
      IconCount := 6;
    for J := 0 to IconCount - 1 do
    begin
      Image := TImageGI.Create(Panel);
      Image.SetImagePath('GI,Bm.FormGoods2.' + GiResourceSuffix + 'Goods' + IntToStr(I + 1));
      { Unlike the market row, native cargo-icon spacing does not use GiScalePixels. }
      if I in [4, 5, 6] then
        Image.SetPosition(Classes.Point(J * 12, 0))
      else
        Image.SetPosition(Classes.Point(J * 11, 0));
      Image.SetDepth(J);
      Image.SetSize(Image.GetContentSize);
    end;
    Color := '';
    if LocalPlayer.CargoGoods[Good].Count < 0 then
      RaiseWideMessage('Player.FGoods[it].Cnt<0')
    else if LocalPlayer.CargoGoods[Good].Count = 0 then
      Color := OutOfStockColor;
    (GetByName('TovCnt' + IntToStr(I + 10)) as TLabelGI)
        .SetText(WrapTextInColor(IntToStr(LocalPlayer.CargoGoods[Good].Count), Color));
    (GetByName('TovPrice' + IntToStr(I + 10)) as TLabelGI)
        .SetText(WrapTextInColor(IntToStr(LocalPlayer.ShopGoodsSellPrice(Good, nil)), Color));
  end;
  if LocalPlayer.IsOnPlanet then
    Location := LocalPlayer.CurrentPlanet
  else if LocalPlayer.IsDockedToShip then
    Location := LocalPlayer.DockedTo
  else if LocalPlayer.InNormalSpace then
    Location := LocalHuman.TalkShip
  else
    Location := nil;
  with GetByName('UserMsgAdd') as TGraphButtonGI do
    if LocalPlayer.InNormalSpace then
      SetDisabled(True)
    else
      SetDisabled(FindPlayerBubbleByText(BuildPriceText(Location), False) <> nil);
end;

procedure TfGoodsShop2.GoodsMouseUp(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
var
  I, Index, Count, Price, Maximum, TotalLimit, Available, Limit: Integer;
  OverMarket, OverCargo: Boolean;
  Description: WideString;
begin
  OverMarket := False;
  OverCargo := False;
  if (GetByName('DownLeft') as TImageGI).HitTestPixel(Point) then
    OverMarket := True
  else if (GetByName('DownRight') as TImageGI).HitTestPixel(Point) then
    OverCargo := True
  else
  begin
    if DraggedGoodsIndex >= 0 then
    begin
      DraggedGoodsIndex := -1;
      UpdateActionCursor(False);
      RefreshGoodsDisplay;
    end;
    Exit;
  end;
  Index := -1;
  for I := 0 to 7 do
  begin
    with GetByName('Tov' + IntToStr(I)) as TGraphButtonGI do
      if ContainsPoint(GetCursorPoint) then
      begin
        Index := I;
        Break;
      end;
    with GetByName('Tov' + IntToStr(I + 10)) as TGraphButtonGI do
      if ContainsPoint(GetCursorPoint) then
      begin
        Index := I + 10;
        Break;
      end;
  end;
  if (Index < 0)
      and ((DraggedGoodsIndex < 0)
          or (OverMarket and (DraggedGoodsIndex >= 0) and (DraggedGoodsIndex < 10))
          or (OverCargo and (DraggedGoodsIndex >= 10) and (DraggedGoodsIndex < 20))) then
  begin
    DraggedGoodsIndex := -1;
    UpdateActionCursor(False);
    RefreshGoodsDisplay;
  end
  else if (DraggedGoodsIndex < 0)
      or ((DraggedGoodsIndex >= 0) and (DraggedGoodsIndex < 10) and (Index >= 0) and (Index < 10))
      or ((DraggedGoodsIndex >= 10)
          and (DraggedGoodsIndex < 20)
          and (Index >= 10)
          and (Index < 20)) then
  begin
    if Index = DraggedGoodsIndex then
      DraggedGoodsIndex := -1
    else if GetAvailableGoodsCount(Index) > 0 then
      DraggedGoodsIndex := Index;
    UpdateActionCursor(False);
    RefreshGoodsDisplay;
    with GetByName('Tov' + IntToStr(Index)) as TGraphButtonGI do
    begin
      SetDown(False);
      SetHovered(False);
      SetHovered(True);
    end;
  end;
  if DraggedGoodsIndex >= 0 then
  begin
    Count := GetMaximumTradeCount(DraggedGoodsIndex, False);
    if (Count <= 0)
        and ((DraggedGoodsIndex >= 10)
            or LocalPlayer.InNormalSpace
            or (GetMaximumTradeCount(DraggedGoodsIndex, True) <= 0)) then
    begin
      if LocalPlayer.InNormalSpace then
      begin
        if (DraggedGoodsIndex >= 10) and (DraggedGoodsIndex < 20) then
        begin
          if PartnerCargoLimit <= 0 then
            ShowMessageBoxGI(
                Self,
                LocalHuman.TalkShip.LookupTalkText('Talk.Trade.NoSpace'),
                mbgCancel or mbgError
            )
          else
            ShowMessageBoxGI(
                Self,
                LocalHuman.TalkShip.LookupTalkText('Talk.Trade.NoMoney'),
                mbgOK or mbgError
            );
        end
        else if DraggedGoodsIndex < 10 then
          if LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[DraggedGoodsIndex]).Count > 0 then
          begin
            if LocalPlayer.GetCargoFreeSpace <= 0 then
              FlashCargoWarning;
            if LocalPlayer.ShopGoodsPurchasePrice(ShopGoodsOrder[DraggedGoodsIndex], nil)
                > LocalPlayer.Money then
              FlashMoneyWarning;
            DraggedGoodsIndex := -1;
            UpdateActionCursor(False);
            RefreshGoodsDisplay;
            BreakUiMessage;
            Exit;
          end;
      end
      else if DraggedGoodsIndex < 10 then
        if LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[DraggedGoodsIndex]).Count > 0 then
        begin
          if LocalPlayer.GetCargoFreeSpace <= 0 then
            MainPanel.FlashCargoWarning;
          if LocalPlayer.ShopGoodsPurchasePrice(ShopGoodsOrder[DraggedGoodsIndex], nil)
              > LocalPlayer.Money then
            MainPanel.FlashMoneyWarning;
        end;
    end
    else
    begin
      Limit := Max(0, Count);
      if DraggedGoodsIndex < 10 then
      begin
        Description :=
            FormatText1(
                LocalizedText('FormGS.Buy'),
                '<color=0,50,200>',
                '<Name>',
                LowerCaseWideString(GoodsMarket[ShopGoodsOrder[DraggedGoodsIndex mod 10]].TradeName)
            );
        Price := LocalPlayer.ShopGoodsPurchasePrice(ShopGoodsOrder[DraggedGoodsIndex mod 10], nil);
        Maximum := LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[DraggedGoodsIndex]).Count;
        Available := LocalPlayer.GetCargoFreeSpace;
        TotalLimit := LocalPlayer.Money;
        if not LocalPlayer.InNormalSpace then
          Limit := Min(Maximum, TotalLimit div Price);
      end
      else
      begin
        Description :=
            FormatText1(
                LocalizedText('FormGS.Sell'),
                '<color=0,50,200>',
                '<Name>',
                LowerCaseWideString(GoodsMarket[ShopGoodsOrder[DraggedGoodsIndex mod 10]].TradeName)
            );
        Price := LocalPlayer.ShopGoodsSellPrice(ShopGoodsOrder[DraggedGoodsIndex mod 10], nil);
        Maximum := LocalPlayer.CargoGoods[ShopGoodsOrder[DraggedGoodsIndex - 10]].Count;
        if not LocalPlayer.InNormalSpace then
        begin
          Available := 1000000000;
          TotalLimit := 1000000000;
        end
        else
        begin
          Available := PartnerCargoLimit;
          TotalLimit := PartnerMoneyLimit;
          Limit := 1000000000;
        end;
      end;
      Count := Max(0, Count);
      if ShowCountDialog(
              Self,
              'GI,' + GetItemTypeBitmapPath(TItemType(ShopGoodsOrder[DraggedGoodsIndex mod 10])),
              Description,
              0,
              Maximum,
              Limit,
              Price,
              Max(0, Available),
              TotalLimit,
              Count)
          = 1 then
      begin
        if (GetMaximumTradeCount(DraggedGoodsIndex, False) < Count)
            and (DraggedGoodsIndex >= 10)
            and LocalPlayer.InNormalSpace then
        begin
          if Count > PartnerCargoLimit then
            ShowMessageBoxGI(
                Self,
                LocalHuman.TalkShip.LookupTalkText('Talk.Trade.NoSpace'),
                mbgCancel or mbgError
            )
          else
            ShowMessageBoxGI(
                Self,
                LocalHuman.TalkShip.LookupTalkText('Talk.Trade.NoMoney'),
                mbgOK or mbgError
            );
        end
        else if (Count > 0)
            and (GetMaximumTradeCount(DraggedGoodsIndex, not LocalPlayer.InNormalSpace) >= Count) then
        begin
          // Native legality check uses the hovered row, even when a different
          // row supplied the dragged good; preserve that original selection.
          if LocalPlayer.IsCargoGoodIllegalOnCurrentPlanet(ShopGoodsOrder[Index mod 10]) then
            if ShowMessageBoxGI(
                    Self,
                    LanguageDataConfig.GetParamByPathOrMarker('FormGS.NotPermitGoods'),
                    mbgOK or mbgCancel)
                <> mbgResultOK then
            begin
              DraggedGoodsIndex := -1;
              UpdateActionCursor(False);
              RefreshGoodsDisplay;
              FinishModalTrade;
              BreakUiMessage;
              Exit;
            end;
          if not LocalPlayer.InNormalSpace then
            aCalc.WaitForTurnCalculationUI;
          if DraggedGoodsIndex < 10 then
          begin
            SoundManager.PlaySound('Sound.Buy');
            TradeGoods(ShopGoodsOrder[DraggedGoodsIndex], Count, False);
          end
          else
          begin
            SoundManager.PlaySound('Sound.Sell');
            TradeGoods(ShopGoodsOrder[DraggedGoodsIndex - 10], Count, True);
          end;
          if not LocalPlayer.InNormalSpace then
            aCalc.WaitForTurnCalculationUI;
          if LocalPlayer.IsOnPlanet then
            if LocalPlayer.CurrentPlanet.GetRelationLevelToShip(LocalPlayer) = rlHostile then
            begin
              RequestedScreenId := screenGovernment;
              RequestClose(1);
            end;
        end;
      end;
    end;
    DraggedGoodsIndex := -1;
    UpdateActionCursor(False);
    RefreshGoodsDisplay;
    FinishModalTrade;
  end;
  BreakUiMessage;
end;

procedure TfGoodsShop2.GoodsRightMouseDown(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
begin
  if DraggedGoodsIndex >= 0 then
  begin
    DraggedGoodsIndex := -1;
    UpdateActionCursor(False);
    RefreshGoodsDisplay;
  end;
end;

procedure TfGoodsShop2.GoodsMouseMove(Sender: TObjectGI; KeyState: Cardinal; Point: TPoint);
var
  Index, Count, Price: Integer;
  Control: TObjectGI;
  I, Profit: Integer;
  Action, Color, Text: WideString;
  Good: Byte;
begin
  if LocalPlayer = nil then
    Exit;
  Index := -1;
  Text := '';
  if DraggedGoodsIndex >= 0 then
    Index := DraggedGoodsIndex
  else
    for I := 0 to 7 do
    begin
      Control := GetByName('Tov' + IntToStr(I));
      with Control as TGraphButtonGI do
        if ContainsPoint(GetCursorPoint) then
        begin
          Index := I;
          Break;
        end;
      Control := GetByName('Tov' + IntToStr(I + 10));
      with Control as TGraphButtonGI do
        if ContainsPoint(GetCursorPoint) then
        begin
          Index := I + 10;
          Break;
        end;
    end;
  if Index >= 0 then
  begin
    Good := ShopGoodsOrder[Index mod 10];
    if ((Index < 10) and (LocalPlayer.GetLocationGoodsEntry(Good).Count > 0))
        or ((Index >= 10) and (LocalPlayer.CargoGoods[Good].Count > 0)) then
    begin
      if Index < 10 then
      begin
        Action := 'Buy';
        Price := LocalPlayer.ShopGoodsPurchasePrice(Good, nil);
        Count := LocalPlayer.GetLocationGoodsEntry(Good).Count;
        Profit := 0;
      end
      else
      begin
        Action := 'Sale';
        Price := LocalPlayer.ShopGoodsSellPrice(Good, nil);
        Count := LocalPlayer.CargoGoods[Good].Count;
        Profit :=
            LocalPlayer.ShopGoodsSellPrice(Good, nil)
                - Integer(Round(LocalPlayer.GetAverageCargoCost(Good)));
      end;
      Text := LookupLocalizedTextByKey('FormGS.' + Action + 'Help');
      ReplaceTextToken(Text, '<Goods>', GoodsMarket[Good].TradeName, '<color=255,240,100>');
      ReplaceTextToken(Text, '<Count>', IntToStr(Count), '<color=255,240,100>');
      ReplaceTextToken(Text, '<Cost>', IntToStr(Price), '<color=255,240,100>');
      if Profit > 0 then
        Color := '<color=0,255,0>'
      else if Profit < 0 then
        Color := '<color=255,0,0>'
      else if Profit = 0 then
        Color := '';
      ReplaceTextToken(
          Text,
          '<OldCost>',
          IntToStr(Round(LocalPlayer.GetAverageCargoCost(Good))),
          Color
      );
      ReplaceTextToken(Text, '<Profit>', IntToStr(Profit), '<color=255,240,100>');
    end
    else if Index < 10 then
    begin
      if LocalPlayer.IsOutsideStarSpace then
        Text :=
            FormatText1(
                LookupLocalizedTextByKey('FormGS.NotGoodsForBuyHelp'),
                '<color=255,240,100>',
                '<Goods>',
                LowerCaseWideString(GoodsMarket[Good].DisplayName)
            )
      else
        Text :=
            FormatText1(
                LookupLocalizedTextByKey('FormGS.NotGoodsForBuyHelpInShip'),
                '<color=255,240,100>',
                '<Goods>',
                LowerCaseWideString(GoodsMarket[Good].DisplayName)
            );
    end
    else
      Text :=
          FormatText1(
              LookupLocalizedTextByKey('FormGS.NotGoodsForSaleHelp'),
              '<color=255,240,100>',
              '<Goods>',
              LowerCaseWideString(GoodsMarket[Good].DisplayName)
          );
  end;
  if (HoveredControl = nil) or (HoveredControl.HelpText = '') then
    ShowHelpText(Text, Text <> '');
end;

procedure TfGoodsShop2.UpdateActionCursor(CanTake: Boolean);
var
  Found: Boolean;
  Index: Integer;
begin
  if LocalPlayer = nil then
    Exit;
  if DraggedGoodsIndex >= 0 then
    SetCursorImage(
        'GI,' + GetItemTypeBitmapPath(TItemType(ShopGoodsOrder[DraggedGoodsIndex mod 10])),
        Classes.Point(16, 16)
    )
  else
  begin
    Found := False;
    for Index := 0 to 7 do
    begin
      with GetByName('Tov' + IntToStr(Index)) as TGraphButtonGI do
        if ContainsPoint(GetCursorPoint) then
          if LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[Index]).Count > 0 then
          begin
            Found := True;
            Break;
          end;
      with GetByName('Tov' + IntToStr(Index + 10)) as TGraphButtonGI do
        if ContainsPoint(GetCursorPoint) then
          if LocalPlayer.CargoGoods[ShopGoodsOrder[Index]].Count > 0 then
          begin
            Found := True;
            Break;
          end;
    end;
    if Found then
    begin
      if not IsCursorImageSelected('Take') then
        SetCursorByName('Take');
    end
    else if not IsCursorImageSelected('Main') then
      SetCursorByName('Main');
  end;
end;

procedure TfGoodsShop2.GoodsMouseEnter(Sender: TObjectGI);
begin
  UpdateActionCursor(False);
end;

procedure TfGoodsShop2.GoodsMouseLeave(Sender: TObjectGI);
begin
  UpdateActionCursor(False);
end;

function TfGoodsShop2.GetMaximumTradeCount(Index: Integer; IgnoreCargoSpace: Boolean): Integer;
var
  Total: Double;
begin
  if (Index >= 0) and (Index < 10) then
  begin
    Result := LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[Index]).Count;
    if (LocalPlayer.GetCargoFreeSpace < Result) and not IgnoreCargoSpace then
      Result := LocalPlayer.GetCargoFreeSpace;
    Total := Result;
    Total := LocalPlayer.ShopGoodsPurchasePrice(ShopGoodsOrder[Index], nil) * Total;
    if (Result * LocalPlayer.ShopGoodsPurchasePrice(ShopGoodsOrder[Index], nil) > LocalPlayer.Money)
        or (Total > 100000000) then
      Result := LocalPlayer.Money div LocalPlayer.ShopGoodsPurchasePrice(ShopGoodsOrder[Index], nil);
  end
  else
  begin
    Result := LocalPlayer.CargoGoods[ShopGoodsOrder[Index - 10]].Count;
    if LocalPlayer.InNormalSpace then
    begin
      if PartnerCargoLimit < Result then
        Result := PartnerCargoLimit;
      if Result * LocalHuman.TalkShip.ShopGoodsSellPrice(ShopGoodsOrder[Index - 10], nil)
          > PartnerMoneyLimit then
        Result :=
            PartnerMoneyLimit div LocalHuman.TalkShip.ShopGoodsSellPrice(ShopGoodsOrder[Index - 10], nil);
    end;
  end;
end;

function TfGoodsShop2.GetAvailableGoodsCount(Index: Integer): Integer;
begin
  if (Index >= 0) and (Index < 10) then
    Result := LocalPlayer.GetLocationGoodsEntry(ShopGoodsOrder[Index]).Count
  else
    Result := LocalPlayer.CargoGoods[ShopGoodsOrder[Index - 10]].Count;
end;

function TfGoodsShop2.BuildPriceText(Location: TObject): WideString;
var
  RowNumber, SeparatorLength, Stock: Integer;
  Text, Title, Info, Separator: WideString;
  Good, Index: Byte;
  SavedPlanet: TPlanet;
  SavedDockedTo: TShip;
begin
  if GiResourceVariant = 1 then
    SeparatorLength := 76
  else
    SeparatorLength := 95;
  for RowNumber := 1 to SeparatorLength do
    Separator := Separator + '-';
  if Location is TPlanet then
    Title :=
        FormatText1(
            LocalizedColorText('FormGS.PlanetInfo'),
            '<color=255,240,100>',
            '<Planet>',
            (Location as TPlanet).Name
        )
  else if Location is TRuins then
    Title := WrapTextInColor((Location as TRuins).GetColoredFullName('<color=255,240,100>'), '')
  else if LocalPlayer.InNormalSpace then
    Title := WrapTextInColor(LocalHuman.TalkShip.GetFullName(' '), '<color=255,240,100>');
  Text := '<td=' + IntToStr(GiScalePixels(0)) + '>' + '<align=left>' + Title + '</align>';
  Text :=
      Text
          + '<td='
          + IntToStr(GiScalePixels(230))
          + '>'
          + '<align=center>'
          + WrapTextInColor(Galaxy.FormatTurnDate(Galaxy.CurrentTurn), '<color=0,255,0>')
          + '</align>';
  if Location is TPlanet then
    Info :=
        FormatText1(
            LocalizedColorText('FormGS.StarInfo'),
            '<color=255,240,100>',
            '<Star>',
            (Location as TPlanet).CurrentStar.Name
        )
  else if Location is TShip then
    Info :=
        FormatText1(
            LocalizedColorText('FormGS.StarInfo'),
            '<color=255,240,100>',
            '<Star>',
            (Location as TShip).CurrentStar.Name
        );
  Text :=
      Text
          + '<td='
          + IntToStr(GiScalePixels(400))
          + '>'
          + '<align=center>'
          + WrapTextInColor(Info, '')
          + '</align>';
  Text := Text + #13#10 + Separator;
  Text :=
      Text
          + #13#10
          + '<td='
          + IntToStr(GiScalePixels(10))
          + '>'
          + '<align=center>'
          + WrapTextInColor(LocalizedColorText('FormGS.ColumnNumber'), '<color=255,240,100>')
          + '</align>';
  Text :=
      Text
          + '<td='
          + IntToStr(GiScalePixels(30))
          + '>'
          + '<align=left>'
          + WrapTextInColor(LocalizedColorText('FormGS.ColumnName'), '<color=255,240,100>')
          + '</align>';
  Text :=
      Text
          + '<td='
          + IntToStr(GiScalePixels(190))
          + '>'
          + '<align=center>'
          + WrapTextInColor(LocalizedColorText('FormGS.ColumnCount'), '<color=255,240,100>')
          + '</align>';
  Text :=
      Text
          + '<td='
          + IntToStr(GiScalePixels(300))
          + '>'
          + '<align=center>'
          + WrapTextInColor(LocalizedColorText('FormGS.ColumnCost'), '<color=255,240,100>')
          + '</align>';
  Text :=
      Text
          + '<td='
          + IntToStr(GiScalePixels(410))
          + '>'
          + '<align=center>'
          + WrapTextInColor(LocalizedColorText('FormGS.ColumnLegality'), '<color=255,240,100>')
          + '</align>';
  Text := Text + #13#10 + Separator;
  RowNumber := 1;
  for Index := 0 to 7 do
  begin
    Good := GoodsTextOrder[Index];
    Stock := 0;
    if Location is TPlanet then
      Stock := (Location as TPlanet).Goods[Good].Count
    else if Location is TRuins then
      Stock := (Location as TRuins).ShopGoods[Good].Count
    else
      RaiseWideMessage('no goods shop');
    Text :=
        Text
            + #13#10
            + '<td='
            + IntToStr(GiScalePixels(10))
            + '>'
            + '<align=center>'
            + WrapTextInColor(IntToStr(RowNumber), '')
            + '</align>';
    Inc(RowNumber);
    Text :=
        Text
            + '<td='
            + IntToStr(GiScalePixels(30))
            + '>'
            + ''
            + WrapTextInColor(GoodsMarket[Good].DisplayName, '')
            + '';
    Text :=
        Text
            + '<td='
            + IntToStr(GiScalePixels(190))
            + '>'
            + '<align=center>'
            + WrapTextInColor(IntToStr(Stock), '')
            + '</align>';
    Text :=
        Text
            + '<td='
            + IntToStr(GiScalePixels(285))
            + '><align=right>'
            + WrapTextInColor(IntToStr(LocalPlayer.ShopGoodsPurchasePrice(Good, Location)), '')
            + '</align>';
    Text :=
        Text
            + '<td='
            + IntToStr(GiScalePixels(300))
            + '><align=center>'
            + WrapTextInColor('/', '')
            + '</align>';
    Text :=
        Text
            + '<td='
            + IntToStr(GiScalePixels(335))
            + '><align=right>'
            + WrapTextInColor(IntToStr(LocalPlayer.ShopGoodsSellPrice(Good, Location)), '')
            + '</align>';
    SavedPlanet := LocalPlayer.CurrentPlanet;
    SavedDockedTo := LocalPlayer.DockedTo;
    // Both native writes clear CurrentPlanet; retain the original duplicate assignment.
    LocalPlayer.CurrentPlanet := nil;
    LocalPlayer.CurrentPlanet := nil;
    if Location is TPlanet then
      LocalPlayer.CurrentPlanet := TPlanet(Location)
    else if Location is TRuins then
      LocalPlayer.DockedTo := TShip(Location);
    if not LocalPlayer.IsCargoGoodIllegalOnCurrentPlanet(Good) then
      Info := LookupLocalizedTextByKey('FormGS.LegalityOk')
    else
      Info := WrapTextInColor(LookupLocalizedTextByKey('FormGS.LegalityNo'), '<color=255,0,0>');
    LocalPlayer.CurrentPlanet := SavedPlanet;
    LocalPlayer.DockedTo := SavedDockedTo;
    Text :=
        Text
            + '<td='
            + IntToStr(GiScalePixels(405))
            + '><align=center>'
            + WrapTextInColor(Info, '')
            + '</align>';
  end;
  Result := Text;
end;

procedure TfGoodsShop2.SavePricesClicked(Sender: TObjectGI);
var
  Location: TObject;
begin
  (GetByName('UserMsgAdd') as TGraphButtonGI).SetDisabled(True);
  SoundManager.PlaySound('Sound.UserMsgAdd');
  if LocalPlayer.IsOnPlanet then
    Location := LocalPlayer.CurrentPlanet
  else if LocalPlayer.IsDockedToShip then
    Location := LocalPlayer.DockedTo
  else if LocalPlayer.InNormalSpace then
    Location := LocalHuman.TalkShip
  else
    Location := nil;
  AddOrUpdatePlayerBubble(
      7,
      Galaxy.CurrentTurn,
      BuildPriceText(Location),
      StarMapScreen.GetPriceSnapshotKey(Location)
  );
  MainPanel.RebuildMessageButtons(False);
  FinishModalTrade;
end;

procedure TfGoodsShop2.EndTurnClicked(Sender: TObjectGI);
begin
  if LocalPlayer = nil then
    Exit;
  if LocalPlayer.QueuedTravelTarget <> nil then
    Exit;
  if LocalPlayer.IsDockedToShip
      and (LocalPlayer.DockedTo.TypeId = Byte(rstDominion))
      and (LocalPlayer.DockedTo.Order = soTeleport)
      and (Cardinal(LocalPlayer.DockedTo.OrderStateData) > 0)
      and not LocalPlayer.DockedTo.InHyperspace then
  begin
    RuinsTalkScreen.DepartWithStation(1);
    Exit;
  end;
  if LocalPlayer.IsDockedToShip
      and (LocalPlayer.DockedTo.TypeId = Byte(rstDominion))
      and ((LocalPlayer.DockedTo as TRuins).FlyToStar <> nil)
      and ((LocalPlayer.DockedTo as TRuins).FlyToStar <> LocalPlayer.CurrentStar)
      and ((LocalPlayer.DockedTo as TRuins).FlyDate <= Galaxy.CurrentTurn) then
  begin
    RuinsTalkScreen.DepartWithStation(1);
    Exit;
  end;
  if LocalPlayer.IsDockedToShip
      and (LocalPlayer.DockedTo.TypeId = Byte(rstMilitaryBase))
      and ((LocalPlayer.DockedTo as TRuins).FlyToStar <> nil)
      and ((LocalPlayer.DockedTo as TRuins).FlyToStar <> LocalPlayer.CurrentStar)
      and ((LocalPlayer.DockedTo as TRuins).FlyDate <= Galaxy.CurrentTurn) then
  begin
    if LocalPlayer.Speed <= 0 then
    begin
      RuinsTalkScreen.DepartWithStation(1);
      Exit;
    end;
    StationPanel.TakeOffForStationTravel;
  end
  else
  begin
    (GetByName('UserMsgAdd') as TGraphButtonGI).SetDisabled(False);
    if DraggedGoodsIndex >= 0 then
    begin
      DraggedGoodsIndex := -1;
      UpdateActionCursor(False);
      RefreshGoodsDisplay;
    end;
    if not LocalPlayer.InNormalSpace then
      aCalc.WaitForTurnCalculationUI;
    ReturnShopStock;
    MainPanel.EndTurnClicked(Sender);
    if ExitCode = 0 then
    begin
      OpenShopStock;
      if not LocalPlayer.InNormalSpace then
        aCalc.WaitForTurnCalculationUI;
      RefreshGoodsDisplay;
      MainPanel.RebuildMessageButtons(False);
    end;
  end;
end;

procedure TfGoodsShop2.GalaxyClicked(Sender: TObjectGI);
begin
  AmbientSound.SetVolume(0);
  MainPanel.GalaxyClicked(Sender);
  AmbientSound.SetVolume(1);
end;

procedure TfGoodsShop2.QuestClicked(Sender: TObjectGI);
begin
  AmbientSound.SetVolume(0);
  MainPanel.QuestClicked(Sender);
  AmbientSound.SetVolume(1);
end;

procedure TfGoodsShop2.MenuClicked(Sender: TObjectGI);
begin
  AmbientSound.SetVolume(0);
  MainPanel.MenuClicked(Sender);
  AmbientSound.SetVolume(1);
end;

procedure TfGoodsShop2.ShipClicked(Sender: TObjectGI);
begin
  if ExitCode <> 0 then
    Exit;
  if DraggedGoodsIndex >= 0 then
  begin
    DraggedGoodsIndex := -1;
    UpdateActionCursor(False);
    RefreshGoodsDisplay;
  end;
  AmbientSound.SetVolume(0);
  SetCursorActive(False);
  Present;
  CaptureScreenBackground(True, 0);
  SetCursorActive(True);
  ShipScreen.PlayTransitionSounds := True;
  if not LocalPlayer.InNormalSpace then
    aCalc.WaitForTurnCalculationUI;
  while True do
  begin
    RunShipEquipment(Self);
    MainPanel.RefreshMoneyAndCargo;
    MainPanel.RebuildMessageButtons(False);
    RefreshGoodsDisplay;
    if not ShipScreen.FlagD4 then
      Break;
    SetCursorActive(False);
    DrawQueuedUpdateRects;
    CaptureScreenBackground(True, 0);
    SetCursorActive(True);
  end;
  if not LocalPlayer.InNormalSpace then
    aCalc.WaitForTurnCalculationUI;
  AmbientSound.SetVolume(1);
  if LocalPlayer.IsOnPlanet then
    if LocalPlayer.CurrentPlanet.GetRelationLevelToShip(LocalPlayer) = rlHostile then
    begin
      RequestedScreenId := screenGovernment;
      RequestClose(1);
    end;
end;

procedure TfGoodsShop2.FinishModalTrade;
begin
  if ParentLoop <> nil then
  begin
    FlagEC := True;
    RequestClose(1);
    BreakUiMessage;
  end;
end;

procedure TfGoodsShop2.CaptureMerchantBackground(Sender: TObjectGI);
var
  Position: TPoint;
begin
  if not HardwareRenderingEnabled then
    with GetByName('FaceGB') as TGraphBufGI do
    begin
      SetActive(False);
      if not ShowSystemMouse then
        SetCursorActive(False);
      DrawQueuedUpdateRects;
      if not ShowSystemMouse then
        SetCursorActive(True);
      Position := ToAbsolutePoint(Classes.Point(0, 0));
      GraphBuf.AllocateNative(ClientSize.X, ClientSize.Y);
      Ex_OKGR_Copy_XY_XY_WORD(
          GraphBuf.GetPixels,
          GraphBuf.PitchBytes,
          0,
          0,
          PAnsiChar(ScreenRenderBuffer.GetPixels)
              + Position.X * 2
              + Position.Y * ScreenRenderBuffer.PitchBytes,
          ScreenRenderBuffer.PitchBytes,
          0,
          0,
          ClientSize.X,
          ClientSize.Y
      );
      GraphBuf.FlipHorizontal16;
      SetActive(True);
    end;
end;

procedure TfGoodsShop2.MerchantAnimationComplete(Sender: TObjectGI);
var
  Sequence: Integer;
begin
  if Sender.UserValue = 1 then
  begin
    Sequence := RandomIntRange(1, 5);
    if Sequence in [1, 2] then
      Sequence := 1
    else if Sequence in [3, 4] then
      Sequence := 2
    else if Sequence in [5] then
      Sequence := 3
    else
      Sequence := 1;
  end
  else
    Sequence := 1;
  if Sender.UserValue <> Sequence then
  begin
    Sender.UserValue := Sequence;
    with GetByName('FaceI') as TImageGI do
    begin
      SetImagePath(
          'GI,Bm.Captain.'
              + GiResourceSuffix
              + 'ShopBot'
              + IntToStr(Cardinal(Sender.UserValue))
              + 'i'
      );
      SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
      SetImageKindX(ikxCenter);
      SetImageKindY(ikyCenter);
      SetActive(True);
    end;
    with GetByName('FaceA') as TgaiGI do
    begin
      FirstFrameOnly := not AnimCaptain;
      SetImagePath(
          'Bm.Captain.' + GiResourceSuffix + 'ShopBot' + IntToStr(Cardinal(Sender.UserValue)) + 'a'
      );
      SetHardwareMirrorHorizontal(HardwareRenderingEnabled);
      SequenceIndex := 0;
      UpdateAutoGeometry;
      SetSequenceFrame(0);
      SetImageKindX(ikxCenter);
      SetImageKindY(ikyCenter);
      SetActive(True);
      RestartPlayback;
      CycleCompleteCallback := MerchantAnimationComplete;
    end;
  end;
end;

procedure TfGoodsShop2.CloseClicked(Sender: TObjectGI);
begin
  if ParentLoop <> nil then
  begin
    RequestClose(1);
    BreakUiMessage;
  end;
end;

procedure TfGoodsShop2.RefreshMoneyWarning;
begin
  if MoneyWarningActive and not Odd(MoneyWarningTicks) then
  begin
    GetByName('ADD_WarningMoney').SetActive(True);
    with GetByName('ADD_Money') as TLabelGI do
    begin
      SetTextColor(CurrentPixelFormat.PackRgbBytes(255, 128, 61));
      SetText(IntToStr(LocalPlayer.Money));
      SetActive(True);
    end;
  end
  else
  begin
    GetByName('ADD_WarningMoney').SetActive(False);
    GetByName('ADD_Money').SetActive(False);
  end;
end;

procedure TfGoodsShop2.FlashMoneyWarning;
begin
  if MoneyWarningTimer <> nil then
  begin
    CancelCallbackTimer(MoneyWarningTimer);
    MoneyWarningTimer := nil;
  end;
  MoneyWarningTimer := ScheduleCallbackTimer(100, 100, MoneyWarningTick);
  MoneyWarningActive := True;
  MoneyWarningTicks := 6;
  RefreshMoneyWarning;
end;

procedure TfGoodsShop2.MoneyWarningTick(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  Dec(MoneyWarningTicks);
  if MoneyWarningTicks <= 0 then
  begin
    if MoneyWarningTimer <> nil then
    begin
      CancelCallbackTimer(MoneyWarningTimer);
      MoneyWarningTimer := nil;
    end;
    MoneyWarningActive := False;
  end;
  RefreshMoneyWarning;
end;

procedure TfGoodsShop2.RefreshCargoWarning;
begin
  if CargoWarningActive and not Odd(CargoWarningTicks) then
  begin
    GetByName('ADD_WarningSpace').SetActive(True);
    with GetByName('ADD_Space') as TLabelGI do
    begin
      SetTextColor(CurrentPixelFormat.PackRgbBytes(255, 128, 61));
      SetText(IntToStr(LocalPlayer.GetCargoFreeSpace));
      SetActive(True);
    end;
  end
  else
  begin
    GetByName('ADD_WarningSpace').SetActive(False);
    GetByName('ADD_Space').SetActive(False);
  end;
end;

procedure TfGoodsShop2.FlashCargoWarning;
begin
  if CargoWarningTimer <> nil then
  begin
    CancelCallbackTimer(CargoWarningTimer);
    CargoWarningTimer := nil;
  end;
  CargoWarningTimer := ScheduleCallbackTimer(100, 100, CargoWarningTick);
  CargoWarningActive := True;
  CargoWarningTicks := 6;
  RefreshCargoWarning;
end;

procedure TfGoodsShop2.CargoWarningTick(Timer: PCallbackTimerGI; UserData: PtrInt);
begin
  Dec(CargoWarningTicks);
  if CargoWarningTicks <= 0 then
  begin
    if CargoWarningTimer <> nil then
    begin
      CancelCallbackTimer(CargoWarningTimer);
      CargoWarningTimer := nil;
    end;
    CargoWarningActive := False;
  end;
  RefreshCargoWarning;
end;

procedure TfGoodsShop2.MainPanelKeyDown(Sender: TObjectGI; Key: Cardinal);
begin
  if IsVirtualKeyDown(VK_CONTROL) or IsVirtualKeyDown(VK_SHIFT) or IsVirtualKeyDown(VK_MENU) then
    Exit;
  if (Key = VK_ESCAPE) and (DraggedGoodsIndex >= 0) then
  begin
    DraggedGoodsIndex := -1;
    UpdateActionCursor(False);
    RefreshGoodsDisplay;
  end
  else if (Key = VK_ESCAPE) and LocalPlayer.InNormalSpace then
    CloseClicked(nil)
  else if (Key = VK_SPACE) and not LocalPlayer.InNormalSpace then
  begin
    if GetByName('PM_EndTurn').Active then
      EndTurnClicked(nil);
  end
  else if (Key = Ord('S')) and not LocalPlayer.InNormalSpace then
    ShipClicked(nil)
  else if not LocalPlayer.InNormalSpace then
  begin
    if (Key = Ord('M'))
        or (Key = Ord('R'))
        or (Key = VK_ESCAPE)
        or (Key = VK_F2)
        or (Key = VK_F3) then
      AmbientSound.SetVolume(0);
    MainPanel.ProcessKeyDown(Key);
    PlanetPanel.ProcessKeyDown(Key);
    StationPanel.ProcessKeyDown(Key);
    if (Key = Ord('M'))
        or (Key = Ord('R'))
        or (Key = VK_ESCAPE)
        or (Key = VK_F2)
        or (Key = VK_F3) then
      AmbientSound.SetVolume(1);
  end;
end;

procedure TfGoodsShop2.ShowControlHelp(Sender: TObjectGI; Visible: Boolean);
begin
  if (LocalPlayer <> nil) and LocalPlayer.InNormalSpace then
    with GetByName('GS_Help') as TLabelGI do
    begin
      if (Sender = nil) or (Sender.HelpText = '') then
        Visible := False;
      SetActive(Visible);
      if Visible then
        SetText(Sender.HelpText);
    end
  else
    MainPanel.ShowControlHelp(Sender, Visible);
end;

procedure TfGoodsShop2.ShowHelpText(Value: WideString; Visible: Boolean);
begin
  if (LocalPlayer <> nil) and LocalPlayer.InNormalSpace then
    with GetByName('GS_Help') as TLabelGI do
    begin
      SetActive(Visible);
      if Visible then
        SetText(Value);
    end
  else
    MainPanel.ShowHelpText(Value, Visible);
end;

procedure TfGoodsShop2.ProcessCallbackTimers;
begin
  inherited ProcessCallbackTimers;
  if (ParentLoop <> nil) and (ParentLoop.ExitCode <> 0) and (ExitCode = 0) then
    RequestClose(2);
end;

procedure TfGoodsShop2.ExecuteUiCode(Block: TBlockParEC; Key: Cardinal);
begin
  if MainPanel.NavigationLocked then
    Exit;
  if ExitScreenLoop then
    Exit;
  if TurnCalculationPhase
      in [tcpIdle, tcpGalaxyFinished, tcpPlayerStarFinished, tcpPlayerStarPrepared] then
  begin
    aCalc.WaitForTurnCalculationUI;
    ExecuteGameplayUiCode(Block, Key);
    aCalc.WaitForTurnCalculationUI;
  end;
end;

procedure TfGoodsShop2.SelectMusic;
begin
  if (ActiveLoadPanel <> nil) and (ActiveLoadPanel.GetShutterDirection = -1) then
    Exit;
  if not MusicInPlanetEnabled then
  begin
    MusicManager.RequestFadeOut;
    Exit;
  end;
  if LocalPlayer.IsOnPlanet then
  begin
    if LocalPlayer.CurrentPlanet.OwnerId = Byte(oiPirate) then
    begin
      if not LocalPlayer.CurrentPlanet.IsMainPiratePlanet then
        MusicManager.PlayCategory(
            'Nation.'
                + OwnerInfo[Integer(RaceToOwner(LocalPlayer.CurrentPlanet.RaceId)) and $7F]
                    .InternalName
                + 'Pirate'
        )
      else
        MusicManager.PlayCategory('Nation.PiratePlanetMain');
    end
    else
      MusicManager
          .PlayCategory('Nation.' + OwnerInfo[LocalPlayer.CurrentPlanet.OwnerId].InternalName);
  end
  else if LocalPlayer.IsDockedToShip then
  begin
    if not MusicInPlanetEnabled then
      MusicManager.RequestFadeOut
    else if LocalPlayer.DockedTo.TypeId in [Ord(rstPirateBase), Ord(rstDominion)] then
      MusicManager.PlayCategory(
          'Nation.'
              + OwnerInfo[Integer(RaceToOwner(LocalPlayer.DockedTo.PilotRace)) and $7F].InternalName
              + 'Pirate'
      )
    else
      MusicManager.PlayCategory(
          'Nation.'
              + OwnerInfo[Integer(RaceToOwner(LocalPlayer.DockedTo.PilotRace)) and $7F].InternalName
      );
  end;
end;

function RunGoodsShop(ParentLoop: TMessageLoopGI): Boolean;
begin
  ParentLoop.RootUiObject.NativeHook50;
  GoodsShopScreen.ParentLoop := ParentLoop;
  ParentLoop.ChildLoop := GoodsShopScreen;
  if GoodsShopScreen.Run = 1 then
    Result := True
  else
    Result := False;
  GoodsShopScreen.ParentLoop := nil;
  ParentLoop.ChildLoop := nil;
  ParentLoop.RootUiObject.NativeHook48;
end;

procedure LinkRecoveredTypes;
begin
  TGraphBufGI.ClassName;
  TGraphButtonGI.ClassName;
  TImageGI.ClassName;
  TLabelGI.ClassName;
  TPanelGI.ClassName;
  TPlanet.ClassName;
  TRanger.ClassName;
  TRuins.ClassName;
  TRuinsSE.ClassName;
  TShip.ClassName;
  TgaiGI.ClassName;
end;
end.
