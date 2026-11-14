# Tsuzuri

An iOS, iPadOS and macOS app for reading, translating, narrating and editing the comics and books a user owns. It starts with turning raw manga into narrated, translated panel videos and grows into a Calibre-style EPUB reader and editor.

## Library

**Library**:
The single collection of every Work the user has imported, comics and books together.
_Avoid_: Bookshelf, collection (reserve "collection" for user-made groupings, if added later)

**Work**:
One title in the Library, either a comic or a book; its **kind** is `comic` or `book`, and it has a **reading direction** (right-to-left, left-to-right, later vertical scroll).
_Avoid_: Item, title, series, book (when the kind is unknown)

**Source**:
The file the user imported a Work from (CBZ, ZIP, images, PDF, EPUB).
_Avoid_: Original, upload

## Comic structure

**Chapter**:
An ordered group of Pages within a comic Work; users can split and merge Chapters.
_Avoid_: Episode, issue, volume

**Page**:
One image of a Chapter as it appears in the Source; users can split, merge and reorder Pages.
_Avoid_: Image, scan

**Panel**:
A region of one Page, or of two adjacent Pages, that is the unit of work: detected automatically, then split, merged or adjusted by the user.
_Avoid_: Frame, box, cell

**Bubble**:
A region of a Panel containing text that is read as one utterance, such as a speech balloon or caption; its **text orientation** is horizontal or vertical.
_Avoid_: Balloon, text box

**Line**:
The text of one Bubble in the source language, with its translation.
_Avoid_: Sentence, string

**Speaker**:
The Character who says a Line.
_Avoid_: Voice, actor, owner

**Script**:
All the Lines of a Chapter, in reading order.
_Avoid_: Transcript, subtitles

## Cast

**Character**:
A person or creature who appears across a Work's Panels, with a consistent look and voice in every Render.
_Avoid_: Actor, person, role

**Cast**:
All the Characters of a Work.
_Avoid_: Characters list, roster

## Output

**Render**:
An AI-generated video, with voiced dialogue, in which one or more consecutive Panels are acted out, made in the cloud only when the user asks and pays for it, watched only inside the app, and backed up to the user's iCloud.
_Avoid_: Export, clip, movie

**Read-aloud**:
Live on-device speech of a Panel's Lines, used for Panels that have no Render.
_Avoid_: TTS playback, narration (when no Render exists)

**Player**:
The in-app viewer that steps through a Chapter's Panels in reading order, playing each Panel's Render or its Read-aloud.
_Avoid_: Reader, viewer, video player

**Reading mode**:
How a Chapter is presented: **Story mode** (target-language narration and subtitles) or **Learn mode** (source-language narration with furigana and translated subtitles).
_Avoid_: Fan mode, study mode

**Source language**:
The language the comic is written in; Japanese at launch.
_Avoid_: Original language, input language

**Target language**:
The language translations and narration are produced in; English at launch.
_Avoid_: Output language, user language
