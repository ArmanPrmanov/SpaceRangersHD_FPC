{$EXCESSPRECISION OFF}
{$codepage utf8}
unit aPortText;

// CHANGE: ENHANCEMENT - Texts the port adds that the game's language data lacks (the
// multiplayer players' buttons, money transfers; docs/humans.md, Players). A key the language
// data has wins; otherwise the Russian fallback in a Russian game, else the English one. The
// Russian literals live only here: this source is UTF-8 ({$codepage utf8}), so they reach
// WideString intact, which a unit without the directive would not do.
interface

var
  // Whether the game runs in Russian (GR_Main.SelectedLanguage, set at startup).
  PortTextRussian: Boolean = True;

function PortText(const Key, English, Russian: WideString): WideString;
// Bubbles of a money transfer (aPlayerActions.TransferMoney): <Amount>, <Name>.
function MoneySentText: WideString;
function MoneyReceivedText: WideString;
// The star map's players' buttons (TfStarMap): the menu, the amount, the hints.
function PlayerShipText: WideString;
function PlayerTalkText: WideString;
function PlayerTransferText: WideString;
// <Name>
function TransferCaptionText: WideString;
function TransferNoMoneyText: WideString;
// <Name>, <Star>
function PlayerInStarText: WideString;
// <Name>
function PlayerInHyperspaceText: WideString;

implementation
uses
  aConst;

function PortText(const Key, English, Russian: WideString): WideString;
begin
  Result := LocalizedColorText(Key);
  if Result = '' then
    if PortTextRussian then
      Result := Russian
    else
      Result := English;
end;

function MoneySentText: WideString;
begin
  Result := PortText(
      'Multiplayer.MoneySent',
      'You transferred <Amount> cr to <Name>.',
      'Вы перевели <Amount> кр. игроку <Name>.'
  );
end;

function MoneyReceivedText: WideString;
begin
  Result := PortText(
      'Multiplayer.MoneyReceived',
      '<Name> transferred <Amount> cr to you.',
      '<Name> перевёл вам <Amount> кр.'
  );
end;

function PlayerShipText: WideString;
begin
  Result := PortText('Multiplayer.PlayerShip', 'Ship and hold', 'Корабль и трюм');
end;

function PlayerTalkText: WideString;
begin
  Result := PortText('Multiplayer.PlayerTalk', 'Talk', 'Связаться');
end;

function PlayerTransferText: WideString;
begin
  Result := PortText('Multiplayer.PlayerTransfer', 'Transfer money', 'Перевести деньги');
end;

function TransferCaptionText: WideString;
begin
  Result := PortText(
      'Multiplayer.TransferCaption',
      'Transfer money to <Name>',
      'Перевод денег игроку <Name>'
  );
end;

function TransferNoMoneyText: WideString;
begin
  Result := PortText(
      'Multiplayer.TransferNoMoney',
      'You have no money to transfer.',
      'У вас нет денег для перевода.'
  );
end;

function PlayerInStarText: WideString;
begin
  Result := PortText(
      'Multiplayer.PlayerInStar',
      '<Name> is in the <Star> system.',
      '<Name> находится в системе <Star>.'
  );
end;

function PlayerInHyperspaceText: WideString;
begin
  Result := PortText(
      'Multiplayer.PlayerInHyperspace',
      '<Name> is in hyperspace.',
      '<Name> в гиперпространстве.'
  );
end;

end.
