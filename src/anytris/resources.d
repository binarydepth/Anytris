/**
 * AnyTris resources.
 *
 * License: $(LINK2 http://opensource.org/licenses/zlib-license, Zlib License).
 *
 * Authors: Leandro Motta Barros
 */

module anytris.resources;

import std.exception;
import fewdee.all;
import anytris.constants;


// Loads all resources, check if they look correct.
public void loadResources()
{
   // Bitmaps
   ResourceManager.bitmaps.add("playfield", new Bitmap("data/playfield.png"));
   ResourceManager.bitmaps.add("block", new Bitmap("data/block.png"));

   // Audio streams
   ResourceManager.streams.add("intro", new AudioStream("data/Miris_Magic_Dance.ogg"));
   ResourceManager.streams.add("inGame", new AudioStream("data/Padanaya_Blokov.ogg"));

   // Check if the bitmap dimensions match the expected
   enforce(ResourceManager.bitmaps["playfield"].width == WIN_WIDTH,
           "'playfield' bitmap width is not the expected.");
   enforce(ResourceManager.bitmaps["playfield"].height == WIN_HEIGHT,
           "'playfield' bitmap height is not the expected.");

   enforce(ResourceManager.bitmaps["block"].width == BLOCK_SIZE,
           "'block' bitmap width is not the expected.");
   enforce(ResourceManager.bitmaps["block"].height == BLOCK_SIZE,
           "'block' bitmap height is not the expected.");
}