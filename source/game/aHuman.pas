{$EXCESSPRECISION OFF}
unit aHuman;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - State that belongs to the human at this machine rather than to the
// galaxy. These were separate globals in aGalaxy and aRanger; the fields keep their
// names. It is not part of TPlayer because it outlives the player's ship. Multiplayer
// needs one per human (ROADMAP.md, Phase 4).
interface
uses
  Classes,
  Globals,
  aGalaxy,
  aHold,
  aItem,
  aPlanet,
  aRuins,
  aShip;
type
  // Read back as TGoodsTradePriceEntry, so the layout must match it.
  TGoodsShopTradeRow = record
    Count: Integer;
    MaximumPrice: Single;
    PurchasePrice: Integer;
    BaseSalePrice: Integer;
  end;
  THumanState = record
    // The star the human is in; its day is simulated with the film.
    PlayerStar: TStar;
    PlayerDialogueRequestCount: Byte;
    PendingPlayerFollowTarget: TShip;
    PlayerAutomaticControl: Boolean;
    PlayerEquipmentBrokenThisTurn: Boolean;
    PlayerOldQuests: TList;
    // Tips already shown, one bit each.
    ShownPlayerTips: Cardinal;
    // The message bubbles, guarded by PersistentPlayerMessageLock.
    FirstPersistentPlayerMessage: TMessagePlayer;
    LastPersistentPlayerMessage: TMessagePlayer;
    // The shop the human has open: its stock (aShopStock) and where it came from.
    TemporaryShopSlots: TList;
    TemporaryShopPlanet: TPlanet;
    TemporaryShopStation: TRuins;
    // Ships shown in the hangar's nine slots, by id.
    HangarShipIds: array[0..8] of Integer;
    // The ship screen's hold order (aHold) and the ship it lists.
    PlayerHoldEntries: TList;
    PlayerHoldShip: TShip;
    // What the human holds on the ship screen's cursor (aHoldActions): taken out of the
    // hold, a slot or the storage, and in no galaxy list until it is put down. Origin 0 is
    // the ship, 1 the storage; Slot is where it goes back.
    SelectedHoldKind: TPlayerHoldKind;
    SelectedGoodsIndex: Byte;
    SelectedGoodsQuantity: Integer;
    SelectedGoodsCost: Integer;
    SelectedHoldItem: TItem;
    SelectedHoldOrigin: Integer;
    SelectedHoldSlot: Integer;
    SelectedHoldUsesDisplayOrder: Boolean;
    // The edited ship's own free experience while the screen shows the player's instead;
    // -1 when it does not.
    SavedShipExperience: Integer;
    // Prices while trading with a ship in space.
    TradeRows: array[0..7] of TGoodsShopTradeRow;
    // Whether the star map shows its weapon panel.
    StarMapWeaponPanelOpen: Boolean;
    // The conversation the human is in: with a ship or a planet, and what the turn thread
    // and the conversation screen pass each other.
    TalkShip: TShip;
    TalkPlanet: TPlanet;
    TalkScripted: Boolean;
    TalkType: Byte;
    TalkResponse: Byte;
    TalkText: WideString;
    TalkAmount: Integer;
  end;
var
  LocalHuman: THumanState;
implementation
end.
