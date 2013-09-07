/**
 * The "in game" state -- where the fun lives!
 *
 * License: $(LINK2 http://opensource.org/licenses/zlib-license, Zlib License).
 *
 * Authors: Leandro Motta Barros
 */

module anytris.in_game_state;

import fewdee.all;

/// The "in game" state -- where the fun lives!
public class InGameState: GameState
{
   /// Constructs the state.
   public this()
   {
      // Put resources in easy to access variables
      _bmpPlayField = ResourceManager.bitmaps["playfield"];
      _bmpBlock = ResourceManager.bitmaps["block"];
      _musicBG = ResourceManager.streams["inGame"];

      // Quit if "ESC" is pressed.
      addHandler(
         ALLEGRO_EVENT_KEY_DOWN,
         delegate(in ref ALLEGRO_EVENT event)
         {
            if (event.keyboard.keycode == ALLEGRO_KEY_ESCAPE)
               popState();
         });

      // Draw
      addHandler(
         FEWDEE_EVENT_DRAW,
         delegate(in ref ALLEGRO_EVENT event)
         {
            al_clear_to_color(al_map_rgb(0, 0, 0));
            al_draw_bitmap(_bmpPlayField, 0.0, 0.0, 0);
            al_draw_bitmap(_bmpBlock, 400.0, 400.0, 0);
         });

      // Start the background music
      _musicBG.play();
   }

   /// Destroys the state.
   public ~this()
   {
      _musicBG.stop();
   }

   /// The bitmap with the play field.
   Bitmap _bmpPlayField;

   /// The bitmap with the block that made up pieces.
   Bitmap _bmpBlock;

   /// The background music.
   private AudioStream _musicBG;
}