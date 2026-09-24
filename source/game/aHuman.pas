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
  aPlanet,
  aRuins,
  aShip;
type
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
  end;
var
  LocalHuman: THumanState;
implementation
end.
