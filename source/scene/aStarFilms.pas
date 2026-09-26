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
