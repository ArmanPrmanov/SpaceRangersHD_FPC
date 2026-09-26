{$EXCESSPRECISION OFF}
unit aStarFilms;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: ENHANCEMENT - The films of the stars that hold a human other than the local one
// (ROADMAP.md, Phase 4). The local human's star records its day into PrimaryFilm as before;
// every other star whose day is filmed records into a film of its own here. Humans in one
// star share its film.
interface
uses
  Classes,
  SE_Space,
  aEFilm;
// The film of Star, created on first use.
function StarFilm(Star: TObject): TEFilm;
// Frees the films of stars that are not in Stars.
procedure KeepStarFilms(Stars: TList);
procedure FreeStarFilms;
// A scene object is going away; no film may refer to it.
procedure ReleaseStarFilmReferences(Obj: TObjectSE);
// CHANGE: ENHANCEMENT - Hot-seat: the local human changed from one in OldStar to one in
// NewStar. Local (PrimaryFilm) holds OldStar's film; NewStar's film becomes Local, and Local's
// film becomes OldStar's, so that each star keeps the day prepared for it and the next day's
// film of the local star is the new local human's.
procedure ExchangeLocalStarFilm(var Local: TEFilm; OldStar, NewStar: TObject);
implementation

type
  TStarFilmEntry = class
    Star: TObject;
    Film: TEFilm;
    destructor Destroy; override;
  end;

var
  Entries: TList;

destructor TStarFilmEntry.Destroy;
begin
  Film.Free;
  inherited Destroy;
end;

function StarFilm(Star: TObject): TEFilm;
var
  I: Integer;
  Entry: TStarFilmEntry;
begin
  for I := 0 to Entries.Count - 1 do
  begin
    Entry := TStarFilmEntry(Entries[I]);
    if Entry.Star = Star then
      Exit(Entry.Film);
  end;
  Entry := TStarFilmEntry.Create;
  Entry.Star := Star;
  Entry.Film := TEFilm.Create;
  Entries.Add(Entry);
  Result := Entry.Film;
end;

procedure KeepStarFilms(Stars: TList);
var
  I: Integer;
  Entry: TStarFilmEntry;
begin
  for I := Entries.Count - 1 downto 0 do
  begin
    Entry := TStarFilmEntry(Entries[I]);
    if Stars.IndexOf(Entry.Star) < 0 then
    begin
      Entries.Delete(I);
      Entry.Free;
    end;
  end;
end;

procedure FreeStarFilms;
var
  I: Integer;
begin
  for I := 0 to Entries.Count - 1 do
    TStarFilmEntry(Entries[I]).Free;
  Entries.Clear;
end;

procedure ExchangeLocalStarFilm(var Local: TEFilm; OldStar, NewStar: TObject);
var
  I: Integer;
  Entry, NewEntry: TStarFilmEntry;
  Film: TEFilm;
begin
  if OldStar = NewStar then
    Exit;
  NewEntry := nil;
  for I := Entries.Count - 1 downto 0 do
  begin
    Entry := TStarFilmEntry(Entries[I]);
    if Entry.Star = NewStar then
      NewEntry := Entry
    else if Entry.Star = OldStar then
    begin
      // Only a star that is not the local one has an entry; drop a stale one.
      Entries.Delete(I);
      Entry.Free;
    end;
  end;
  if NewEntry = nil then
  begin
    NewEntry := TStarFilmEntry.Create;
    NewEntry.Film := TEFilm.Create;
    Entries.Add(NewEntry);
  end;
  Film := NewEntry.Film;
  NewEntry.Star := OldStar;
  NewEntry.Film := Local;
  Local := Film;
end;

procedure ReleaseStarFilmReferences(Obj: TObjectSE);
var
  I: Integer;
begin
  for I := 0 to Entries.Count - 1 do
    TStarFilmEntry(Entries[I]).Film.ReleaseObjectReferences(Obj);
end;

initialization
  Entries := TList.Create;
finalization
  FreeStarFilms;
  Entries.Free;
  Entries := nil;
end.
