/**
 * Configuration files (actually, configuration strings), which work even at
 * compile-time and use a Lua-like syntax.
 *
 * License: $(LINK2 http://opensource.org/licenses/zlib-license, Zlib License).
 *
 * Authors: Leandro Motta Barros
 */

module fewdee.config;

import std.array;
import std.conv;
import std.traits;
import fewdee.internal.config_lexer;


/// The possible values a $(D ConfigValue) can have.
public enum ConfigValueType
{
   /// Nil; kind of a non-value.
   NIL,

   /// A number; always floating point.
   NUMBER,

   /// A string.
   STRING,

   /// A Boolean value.
   BOOLEAN,

   /// An associative array of $(D ConfigValue)s, indexed by $(D string)s.
   AA,

   /// A sequential collection of $(D ConfigValue)s.
   LIST,
}


/**
 * A value from a configuration file.
 *
 * This can represent a subset of the values of the Lua programming
 * language. Specifically, this can contain "nil", strings, numbers (which are
 * always floating point) and a subset of what tables can
 * represent.
 *
 * Concerning the supported subset of Lua tables, a $(D ConfigValue) can only
 * represent tables in which all values are indexed by string keys, or tables
 * that are used as lists. These two cases are internally represented as
 * separate types (respectively, $(D ConfigValueType.AA) and $(D
 * ConfigValueType.LIST)).
 *
 * By the way, this brings an interesting question, which doesn't exist in the
 * real Lua world: is $(D { }) considered a $(D ConfigValueType.AA) or a $(D
 * ConfigValueType.LIST)? Well, based on the fact that $(D { }) doesn't have any
 * string key, we use the convention that it is a $(D ConfigValueType.LIST). You
 * may want to use $(D isEmptyTable()) to check if something is either an empty
 * associative array or an empty list.
 */
public struct ConfigValue
{
   /**
    * Copy-constructs a $(D ConfigValue).
    *
    * Deep copies lists and associative arrays.
    */
   public this(const(ConfigValue) data)
   {
      _type = data._type;
      final switch(_type)
      {
         case ConfigValueType.NIL:
            break;

         case ConfigValueType.NUMBER:
            _number = data._number;
            break;

         case ConfigValueType.STRING:
            _string = data._string;
            break;

         case ConfigValueType.BOOLEAN:
            _boolean = data._boolean;
            break;

         case ConfigValueType.AA:
            makeAA();
            foreach(k, v; data._aa)
               _aa[k] = ConfigValue(v);
            break;

         case ConfigValueType.LIST:
            makeList();
            _list.length = data._list.length;
            foreach(i, v; data._list)
               _list[i] = ConfigValue(v);
            break;
      }
   }

   /// Constructs a $(D ConfigValue) with a "string" type.
   public this(string data)
   {
      _type = ConfigValueType.STRING;
      _string = data;
   }

   /// Constructs a $(D ConfigValue) with a "number" type.
   public this(double data)
   {
      _type = ConfigValueType.NUMBER;
      _number = data;
   }

   /// Constructs a $(D ConfigValue) with a "Boolean" type.
   public this(bool data)
   {
      _type = ConfigValueType.BOOLEAN;
      _boolean = data;
   }

   /// Constructs a $(D ConfigValue) with an "associative array" type.
   public this(ConfigValue[string] data)
   {
      _type = ConfigValueType.AA;
      _aa = data;
   }

   /// Constructs a $(D ConfigValue) with a "list" type.
   public this(ConfigValue[] data)
   {
      _type = ConfigValueType.LIST;
      _list = data;
   }

   /// Assigns a string to this $(D ConfigValue).
   public final string opAssign(string data)
   {
      _type = ConfigValueType.STRING;
      _string = data;
      return data;
   }

   /// Assigns a number to this $(D ConfigValue).
   public final double opAssign(double data)
   {
      _type = ConfigValueType.NUMBER;
      _number = data;
      return data;
   }

   /// Assigns a number to this $(D ConfigValue).
   public final int opAssign(int data)
   {
      _type = ConfigValueType.NUMBER;
      _number = data;
      return data;
   }

   /// Assigns a Boolean value to this $(D ConfigValue).
   public final bool opAssign(bool data)
   {
      _type = ConfigValueType.BOOLEAN;
      _boolean = data;
      return data;
   }

   /// Assigns an associative array to this $(D ConfigValue).
   public final ConfigValue[string]opAssign(ConfigValue[string] data)
   {
      _type = ConfigValueType.AA;
      _aa = data;
      return data;
   }

   /// Assigns a list to this $(D ConfigValue).
   public final ConfigValue[] opAssign(ConfigValue[] data)
   {
      _type = ConfigValueType.LIST;
      _list = data;
      return data;
   }

   /**
    * Assuming a $(D ConfigValue) of type $(D ConfigValueType.LIST), returns the
    * value at a given index.
    *
    * When using the non-const version and using an index that is larger than
    * the list length, the list resized (with default-constructed
    * $(D ConfigValue)s as the new items) and the new item at $(D index) is
    * returned.
    *
    * Using this yields code like $(D value[0]), which is more readable than $(D
    * value.asList[0]).
    */
   public ref const(ConfigValue) opIndex(size_t index) const
   in
   {
      assert(
         _type == ConfigValueType.LIST,
         "Trying to index with an integer a ConfigValue that is not a list");
      assert(
         index < _list.length,
         "Out-of-bounds index for ConfigValue");
   }
   body
   {
      return _list[index];
   }

   /// Ditto
   public ref ConfigValue opIndex(size_t index)
   in
   {
      assert(
         _type == ConfigValueType.LIST,
         "Trying to index with an integer a ConfigValue that is not a list");
   }
   body
   {
      if (index >= _list.length)
         _list.length = index + 1;
      return _list[index];
   }

   /**
    * Assuming a $(D ConfigValue) of type $(D ConfigValueType.AA), returns the
    * value associated with a given key.
    *
    * When using the non-const version, if there is no value associated with $(D
    * key), associate a brand new $(D ConfigValue) with $(D key) and return it.
    *
    * Using this yields code like $(D value["key"]), which is more readable than
    * $(D value.asAA["key"]).
    */
   public ref const(ConfigValue) opIndex(string key) const
   in
   {
      assert(_type == ConfigValueType.AA,
             "Trying to index with a string a ConfigValue that is not an "
             "associative array");
      assert(key in _aa, "Key not found in ConfigValue");
   }
   body
   {
      return _aa[key];
   }

   // Ditto
   public ref ConfigValue opIndex(string key)
   in
   {
      assert(_type == ConfigValueType.AA,
             "Trying to index with a string a ConfigValue that is not an "
             "associative array");
   }
   body
   {
      auto p = key in _aa;
      if (p)
      {
         return *p;
      }
      else
      {
         _aa[key] = ConfigValue();
         return _aa[key];
      }
   }

   /**
    * Assuming a $(D ConfigValue) of type $(D ConfigValueType.AA) or $(D
    * ConfigValueType.LIST), returns the number of elements stored in the
    * associative array or list.
    *
    * Using this yields code like $(D value.length), which is more readable than
    * $(D value.asAA.length).
    */
   public @property size_t length() inout
   in
   {
      assert(_type == ConfigValueType.AA || _type == ConfigValueType.LIST,
             "Can only take length of associative arrays and lists.");
   }
   body
   {
      if (isAA)
         return _aa.length;
      else if (isList)
         return _list.length;
      else
         assert(false, "Only AAs and lists are accepted here");
   }

   /**
    * Equality operator. Comparing with the "wrong" type is not an error -- it
    * simply returns $(D false) in this case.
    */
   public bool opEquals(T)(T value) const
   {
      static if(is(T == string))
      {
         return isString && _string == value;
      }
      else if(is(T == bool))
      {
         return isBoolean && _boolean == value;
      }
      else if (isNumeric!T)
      {
         return isNumber && _number == value;
      }
   }

   ///
   unittest
   {
      auto stringValue = ConfigValue("xyz");
      auto numberValue = ConfigValue(123);
      auto booleanValue = ConfigValue(true);

      assert(stringValue == "xyz");
      assert(stringValue != "abc");

      assert(numberValue == 123);
      assert(numberValue != 999);

      assert(booleanValue == true);
      assert(booleanValue != false);

      assert(stringValue != 123);
      assert(stringValue != false);
      assert(numberValue != "xyz");
      assert(numberValue != true);
      assert(booleanValue != "xyz");
      assert(booleanValue != 1);
      assert(booleanValue != 0);
   }

   /// Returns the type of this $(D ConfigValue).
   public @property ConfigValueType type() inout { return _type; }

   // Is this value a string?
   public @property bool isString() inout
   {
      return _type == ConfigValueType.STRING;
   }

   // Is this value a number?
   public @property bool isNumber() inout
   {
      return _type == ConfigValueType.NUMBER;
   }

   // Is this value a Boolean?
   public @property bool isBoolean() inout
   {
      return _type == ConfigValueType.BOOLEAN;
   }

   // Is this value nil?
   public @property bool isNil() inout
   {
      return _type == ConfigValueType.NIL;
   }

   // Is this value a list?
   public @property bool isList() inout
   {
      return _type == ConfigValueType.LIST;
   }

   // Is this value an associative array?
   public @property bool isAA() inout
   {
      return _type == ConfigValueType.AA;
   }

   /// Gets the value assuming it is a string.
   public @property string asString() inout
   in
   {
      assert(_type == ConfigValueType.STRING);
   }
   body
   {
      return _string;
   }

   /// Gets the value assuming it is a number.
   public @property double asNumber() inout
   in
   {
      assert(_type == ConfigValueType.NUMBER);
   }
   body
   {
      return _number;
   }

   /// Gets the value assuming it is a Boolean.
   public @property bool asBoolean() inout
   in
   {
      assert(_type == ConfigValueType.BOOLEAN);
   }
   body
   {
      return _boolean;
   }

   /// Gets the value assuming it is a table of values indexed by strings.
   public @property const(ConfigValue[string]) asAA() inout
   in
   {
      assert(_type == ConfigValueType.AA);
   }
   body
   {
      return _aa;
   }

   /// Gets the value assuming it is a list of values.
   public @property const(ConfigValue[]) asList() inout
   in
   {
      assert(_type == ConfigValueType.LIST);
   }
   body
   {
      return _list;
   }

   /// Checks whether this is an empty table or list.
   public @property bool isEmptyTable() inout
   {
      return (_type == ConfigValueType.LIST && asList.length == 0)
         || (_type == ConfigValueType.AA && asAA.length == 0);
   }

   /// Make this an empty list.
   public final void makeList()
   {
      ConfigValue[] list;
      this = list;
   }

   /// Make this an empty associative array.
   public final void makeAA()
   {
      ConfigValue[string] aa;
      this = aa;
   }


   /// The type of this $(D ConfigValue); "nil" by default.
   private ConfigValueType _type;

   /**
    * The value stored in this $(D ConfigValue).
    *
    * TODO: This should be a $(D union), but as of DMD 2.063.2, the compiler
    *    doesn't support $(D union) in CTFE, so we'll keep this as a $(D struct)
    *    for now. When the compiler gets smarter, we'll just have to change this
    *    to $(D union) and everything should work.
    */
   private struct
   {
      string _string;
      double _number;
      bool _boolean;
      ConfigValue[string] _aa;
      ConfigValue[] _list;
   }
}

// Some simple minded tests for ConfigValue.
unittest
{
   // Nil
   ConfigValue nilValue;
   assert(nilValue.type == ConfigValueType.NIL);
   assert(nilValue.isNil);

   // String
   enum aString = "I am a string!";
   auto stringValue = ConfigValue(aString);

   assert(stringValue.type == ConfigValueType.STRING);
   assert(stringValue.isString);
   assert(stringValue.asString == aString);
   assert(stringValue == aString);

   // Number
   enum aNumber = 171.171;
   auto numberValue = ConfigValue(aNumber);

   assert(numberValue.type == ConfigValueType.NUMBER);
   assert(numberValue.isNumber);
   assert(numberValue.asNumber == aNumber);
   assert(numberValue == aNumber);

   // Boolean
   enum aBoolean = true;
   auto booleanValue = ConfigValue(aBoolean);

   assert(booleanValue.type == ConfigValueType.BOOLEAN);
   assert(booleanValue.isBoolean);
   assert(booleanValue.asBoolean == aBoolean);
   assert(booleanValue == aBoolean);

   // AA
   ConfigValue[string] aTable = [
      "foo": ConfigValue(1.1),
      "bar": ConfigValue("baz")
   ];
   auto tableValue = ConfigValue(aTable);

   assert(tableValue.type == ConfigValueType.AA);
   assert(tableValue.isAA);

   assert("foo" in tableValue.asAA);
   assert(tableValue["foo"].isNumber);
   assert(tableValue["foo"] == 1.1);

   assert("bar" in tableValue.asAA);
   assert(tableValue["bar"].isString);
   assert(tableValue["bar"].asString == "baz");

   // List
   auto aList = [ ConfigValue(-0.3), ConfigValue("blah") ];
   auto listValue = ConfigValue(aList);

   assert(listValue.type == ConfigValueType.LIST);
   assert(listValue.isList);

   assert(listValue.length == aList.length);
   assert(listValue.length == 2);

   assert(listValue[0].isNumber);
   assert(listValue[0] == -0.3);

   assert(listValue[1].isString);
   assert(listValue[1].asString == "blah");
}

// Tests ConfigValue.isEmptyTable
unittest
{
   // Non-empty list
   auto fullListValue = ConfigValue([ ConfigValue(-0.3), ConfigValue("blah") ]);
   assert(!fullListValue.isEmptyTable);

   // Empty list
   ConfigValue[] aList;
   auto emptyListValue = ConfigValue(aList);
   assert(emptyListValue.isEmptyTable);

   // Non-empty AA
   ConfigValue[string] aTable = [
      "foo": ConfigValue(1.1),
      "bar": ConfigValue("baz")
   ];
   auto fullAAValue = ConfigValue(aTable);
   assert(!fullAAValue.isEmptyTable);

   // Empty AA
   ConfigValue[string] anEmptyTable;
   auto emptyAAValue = ConfigValue(anEmptyTable);
   assert(emptyAAValue.isEmptyTable);
}

// Tests ConfigValue.asString with backslashes
unittest
{
   enum aString = "I am a string \\ and I have an embedded backslash!";
   auto cv = ConfigValue(aString);

   assert(cv.type == ConfigValueType.STRING);
   assert(cv.isString);
   assert(cv.asString == aString);
   assert(cv == aString);
}


/**
 * Parses and returns one value from a list of tokens; removes the parsed
 * elements from this list of tokens.
 */
private ConfigValue parseValue(ref Token[] tokens)
in
{
   assert(tokens.length > 0);
}
body
{
   switch (tokens[0].type)
   {
      case TokenType.NIL:
      {
         tokens = tokens[1..$];
         return ConfigValue();
      }

      case TokenType.STRING:
      {
         auto res = ConfigValue(tokens[0].asString);
         tokens = tokens[1..$];
         return res;
      }

      case TokenType.NUMBER:
      {
         auto res = ConfigValue(tokens[0].asNumber);
         tokens = tokens[1..$];
         return res;
      }

      case TokenType.BOOLEAN:
      {
         auto res = ConfigValue(tokens[0].asBoolean);
         tokens = tokens[1..$];
         return res;
      }

      case TokenType.OPENING_BRACE:
      {
         if (tokens.length < 2)
            throw new Exception("Table not closed near " ~ tokens[0].rawData);
         else if (tokens[1].isIdentifier)
            return parseAA(tokens);
         else
            return parseList(tokens);
      }

      default:
         throw new Exception("Error parsing near " ~ tokens[0].rawData);
   }
}

// Tests for parseValue(). This is also indirectly tested by whatever tests
// parseConfig().
unittest
{
   with (TokenType)
   {
      // Simple case: nil
      auto tokensNil = [ Token(NIL, "nil") ];
      assert(parseValue(tokensNil).isNil);
      assert(tokensNil == [ ]);

      // Simple case: string
      auto tokensString = [ Token(STRING, "'hello'") ];
      auto stringData = parseValue(tokensString);
      assert(stringData.isString);
      assert(stringData == "hello");
      assert(tokensString == [ ]);

      // Simple case: number
      auto tokensNumber = [ Token(NUMBER, "-8.571") ];
      auto numberData = parseValue(tokensNumber);
      assert(numberData.isNumber);
      assert(numberData == -8.571);
      assert(tokensNumber == [ ]);

      // Simple case: Boolean
      auto tokensBoolean = [ Token(BOOLEAN, "true") ];
      auto booleanData = parseValue(tokensBoolean);
      assert(booleanData.isBoolean);
      assert(booleanData == true);
      assert(tokensBoolean == [ ]);

      // Some shortcuts for the next few tests
      auto openingBrace = Token(OPENING_BRACE, "{");
      auto closingBrace = Token(CLOSING_BRACE, "}");
      auto comma = Token(COMMA, ",");
      auto equals = Token(EQUALS, "=");

      // Empty list
      auto tokensEmptyList = [ openingBrace, closingBrace ];
      auto emptyListData = parseValue(tokensEmptyList);
      assert(emptyListData.isList);
      assert(emptyListData.length == 0);
      assert(tokensEmptyList == [ ]);

      // List (with members)
      auto tokensList = [
         openingBrace,
         Token(NUMBER, "1.11"), comma, Token(STRING, "'abc'"), comma,
         closingBrace ];
      auto listData = parseValue(tokensList);
      assert(listData.isList);
      assert(listData.length == 2);
      assert(listData[0].isNumber);
      assert(listData[0] == 1.11);
      assert(listData[1].isString);
      assert(listData[1] == "abc");
      assert(tokensList == [ ]);

      // Associative array
      auto tokensAA = [
         openingBrace,
         Token(IDENTIFIER, "one"), equals, Token(NUMBER, "1"), comma,
         Token(IDENTIFIER, "two"), equals, Token(NUMBER, "2"), comma,
         Token(IDENTIFIER, "foobar"), equals, Token(STRING, "'baz'"), comma,
         Token(IDENTIFIER, "godMode"), equals, Token(BOOLEAN, "true"), comma,
         closingBrace ];
      auto aaData = parseValue(tokensAA);

      assert(aaData.isAA);
      assert(aaData.length == 4);

      assert("one" in aaData.asAA);
      assert(aaData["one"].isNumber);
      assert(aaData["one"] == 1);

      assert("two" in aaData.asAA);
      assert(aaData["two"].isNumber);
      assert(aaData["two"] == 2);

      assert("foobar" in aaData.asAA);
      assert(aaData["foobar"].isString);
      assert(aaData["foobar"] == "baz");

      assert("godMode" in aaData.asAA);
      assert(aaData["godMode"].isBoolean);
      assert(aaData["godMode"] == true);

      assert(tokensAA == [ ]);
   }
}

/// Like $(D parseValue), but specific for associative arrays.
private ConfigValue parseAA(ref Token[] tokens)
in
{
   assert(tokens.length > 0);
   assert(tokens[0].isOpeningBrace);
}
body
{
   ConfigValue[string] result;

   tokens = tokens[1..$]; // skip opening brace

   while (true)
   {
      // Check for the end of the table
      if (tokens.length == 0)
         throw new Exception("List not closed.");

      if (tokens[0].isClosingBrace)
      {
         tokens = tokens[1..$];
         return ConfigValue(result);
      }

      // Read the key/value pair
      if (tokens.length < 3)
      {
         throw new Exception(
            "Incomplete key/value pair near " ~ tokens[0].rawData);
      }

      if (tokens[0].type != TokenType.IDENTIFIER)
         throw new Exception("Not a valid table key: " ~ tokens[0].rawData);

      if (tokens[1].type != TokenType.EQUALS)
         throw new Exception("Expected =, got " ~ tokens[0].rawData);

      auto key = tokens[0].asIdentifier;
      tokens = tokens[2..$];
      auto value = parseValue(tokens);

      result[key] = value;

      // After the key/value pair, we need either a comma or a closing brace
      if (tokens[0].isComma)
      {
         tokens = tokens[1..$];
      }
      else if (tokens[0].type != TokenType.CLOSING_BRACE)
      {
         throw new Exception("Error parsing table near " ~ tokens[0].rawData);
      }
   }
}

/// Like $(D parseValue), but specific for lists.
private ConfigValue parseList(ref Token[] tokens)
in
{
   assert(tokens.length > 0);
   assert(tokens[0].isOpeningBrace);
}
body
{
   ConfigValue[] result;

   tokens = tokens[1..$]; // skip opening brace

   while (true)
   {
      // Check for the end of the table
      if (tokens.length == 0)
         throw new Exception("List not closed.");

      if (tokens[0].isClosingBrace)
      {
         tokens = tokens[1..$];
         return ConfigValue(result);
      }

      // Read the value
      result ~= parseValue(tokens);

      // After the value, we need either a comma or a closing brace
      if (tokens[0].isComma)
      {
         tokens = tokens[1..$];
      }
      else if (tokens[0].type != TokenType.CLOSING_BRACE)
      {
         throw new Exception("Error parsing list near " ~ tokens[0].rawData);
      }
   }
}


/**
 * Parses a given configuration string, and returns the data read.
 *
 * The format of configuration strings is a subset of the Lua programming
 * language. Why Lua? Because it works great as a data description language and
 * because I use Lua anyway whenever I have to embed a scripting language into
 * some other program something (so to makes sense to use the same format). Why
 * a $(I subset) of Lua? Because I didn't want to re-implement Lua in D; I just
 * wanted to implement something quickly that provided enough data description
 * capabilities for my needs, and which worked at compile-time.
 *
 * So, what's supported? Well, a configuration string is a sequence of
 * assignments in the format "key = value". The key must be a valid identifier
 * (you know, alphanumeric characters and underscores, but not starting with a
 * digit nor being a reserved word like "nil). The values must be one of the
 * following:
 *
 * $(UL
 *    $(LI Numbers. As in standard Lua, they are always floating point numbers
 *       ($(D double)s, to be exact)).
 *    $(LI Strings. They can be written between single or double quotes. The
 *       more exotic string format supported by Lua are not supported
 *       here.)
 *    $(LI Booleans. Either "true" or "false", it goes without saying.)
 *    $(LI Nil. You can use "nil" to represent something invalid; it is a kind
 *       of non-value.)
 *    $(LI Lua tables, with restrictions. Real Lua tables are insanely
 *       versatile; what we support here is just a subset of what Lua
 *       supports. Specifically, two kinds of Lua tables are supported:
 *       $(UL
 *          $(LI Tables in which all keys are (implicitly) numbers. For example,
 *             "{ 'hello', 3.14, nil, -4.3e-6 }" and "{ 5.3, }" fit into this
 *             case. An empty table, "{ }", is also considered to fit into this
 *             case. In a $(D ConfigValue), this type of table is called a
 *             "list", and, unlike in Lua, indices are zero-based.)
 *          $(LI Tables that use only strings as keys, like "{ aNumber = 1.23,
 *             aString = 'hello!', somethingElse = nil, }" and "{ luckyNumber =
 *             13 }". In a $(D ConfigValue), this type of table is called an
 *             "associative array" (often abbreviated to "AA").)
 *       )
 *    )
 * )
 *
 * "Simple" Lua comments are supported, too: "--" starts a comment that
 * continues until the end of the line. And tables can be nested as much as you
 * need.
 *
 * So, here is an example of what would be a valid (though not necessarily a
 * well-designed) configuration string.
 *
 * $(D `
 * --
 * -- Example of configuration string
 * --
 *
 * favoriteColor = "Blue"
 *
 * luckyNumbers = { 13, 55, 171, } -- OK to use trailing comma...
 *
 * unluckyNumbers = { -4.56e-4, +4, .1235 } -- ...but it is not required
 *
 * translationTable = {
 *    one = { 'um', 'eins', 'un' },
 *    two = { 'dois', 'zwei', 'deux' },
 *    three = { 'três', 'drei', 'trois' }
 * }
 *
 * colorBlindMode = true
 * `)
 *
 * Parameters:
 *    data = The configuration data string.
 *
 * Returns: A $(D ConfigValue) of type $(D ConfigValueType.AA) with all the
 *    "top-level key/value pairs found in $(D data).
 *
 * Throws:
 *    Throws an $(D Exception) if parsing fails.
 */
public ConfigValue parseConfig(string data)
out(result)
{
   assert(result.isAA);
}
body
{
   /// Lexes $(D data), returns the list of tokens. Throws on error.
   Token[] tokenize(string data)
   {
      Token[] res;

      while(true)
      {
         Token token;
         data = nextToken(data, token);

         if (token.isError)
            throw new Exception(token.rawData);

         if (token.isEOF)
            return res;

         res ~= token;
      }
   }

   ConfigValue[string] result;

   // Tokenize all input data
   Token[] tokens = tokenize(data);

   // Parse a sequence of 'key = value' entries
   while (true)
   {
      // Check for the end of the input stream.
      if (tokens.length == 0)
         return ConfigValue(result);

      // Read the key = value entry
      if (tokens.length < 3)
      {
         throw new Exception(
            "Incomplete key = value entry near " ~ tokens[0].rawData);
      }

      if (tokens[0].type != TokenType.IDENTIFIER)
         throw new Exception("Not a valid table key: " ~ tokens[0].rawData);

      if (tokens[1].type != TokenType.EQUALS)
         throw new Exception("Expected =, got " ~ tokens[0].rawData);

      auto key = tokens[0].asIdentifier;
      tokens = tokens[2..$];
      auto value = parseValue(tokens);

      result[key] = value;
   }

   assert(false);
}


// Very basic parseConfig() tests.
unittest
{
   // An empty input string yields an empty associative array
   auto v1 = parseConfig("");
   assert(v1.isAA);
   assert(v1.length == 0);

   // An empty pair of braces yields an empty list
   auto v2 = parseConfig("list = {}");
   assert(v2.isAA);
   assert(v2.length == 1);
   assert("list" in v2.asAA);
   assert(v2["list"].isList);
   assert(v2["list"].length == 0);

   // A string value
   auto v3 = parseConfig("x = 'asdf'");
   assert(v3.isAA);
   assert(v3.length == 1);
   assert("x" in v3.asAA);
   assert(v3["x"] == "asdf");

   // A numeric value
   auto v4 = parseConfig("_v = 1.3e-6");
   assert(v4.isAA);
   assert(v4.length == 1);
   assert("_v" in v4.asAA);
   assert(v4["_v"] == 1.3e-6);

   // A Boolean value
   auto v5 = parseConfig("fewDeeRules = true");
   assert(v5.isAA);
   assert("fewDeeRules" in v5.asAA);
   assert(v5["fewDeeRules"] == true);

   // A nil value
   auto v6 = parseConfig("sigh = nil");
   assert(v6.isAA);
   assert(v6.length == 1);
   assert("sigh" in v6.asAA);
   assert(v6["sigh"].isNil);

   // A list
   auto v7 = parseConfig("myList = { +1.2, nil, 'foobar' }");
   assert(v7.isAA);
   assert(v7.length == 1);
   assert("myList" in v7.asAA);
   assert(v7["myList"][0] == 1.2);
   assert(v7["myList"][1].isNil);
   assert(v7["myList"][2] == "foobar");

   // An associative array
   auto v8 = parseConfig("myAA = { first = 1, second = 2, third = 'three' }");
   assert(v8.isAA);
   assert(v8.length == 1);
   assert("myAA" in v8.asAA);
   assert(v8["myAA"]["first"] == 1);
   assert(v8["myAA"]["second"] == 2);
   assert(v8["myAA"]["third"] == "three");
}

/// A few more tests with strings
unittest
{
   assert(parseConfig(`s = "aaa"`)["s"] == "aaa");
   assert(parseConfig(`s = 'aaa'`)["s"] == "aaa");
   assert(parseConfig(`s = '\''`)["s"] == "'");
   assert(parseConfig(`s = ''`)["s"] == "");
   assert(parseConfig(`s=""`)["s"] == "");
}

/// A few more tests with numbers
unittest
{
   assert(parseConfig(`n = 1.111`)["n"] == 1.111);
   assert(parseConfig(`n = -4.11`)["n"] == -4.11);
   assert(parseConfig(`n = .01`)["n"] == .01);
   assert(parseConfig(`n= .01`)["n"] == .01);
   assert(parseConfig(`n =.01e5`)["n"] == .01e5);
   assert(parseConfig(`n =-.01E5`)["n"] == -.01e5);
}

/// A few more tests with Booleans
unittest
{
   assert(parseConfig(`b = true`)["b"] == true);
   assert(parseConfig(`b = false`)["b"] == false);
   assert(parseConfig(`b = true--`)["b"] == true);
   assert(parseConfig(`b = false--true`)["b"] == false);
}

/// More tests with lists
unittest
{
   // No trailing comma, one element
   auto v1 = parseConfig("x = { 'abc' } ");
   assert(v1["x"].isList);
   assert(v1["x"].length == 1);
   assert(v1["x"][0] == "abc");

   // Trailing comma, one element
   auto v2 = parseConfig("x = { 'abc', } ");
   assert(v2["x"].isList);
   assert(v2["x"].length == 1);
   assert(v2["x"][0] == "abc");

   // No trailing comma, multiple elements
   auto v3 = parseConfig("x = { 'abc', 123.4 } ");
   assert(v3["x"].isList);
   assert(v3["x"].length == 2);
   assert(v3["x"][0] == "abc");
   assert(v3["x"][1] == 123.4);

   // Trailing comma, multiple elements
   auto v4 = parseConfig("x = { 'abc', 123.4, } ");
   assert(v4["x"].isList);
   assert(v4["x"].length == 2);
   assert(v4["x"][0] == "abc");
   assert(v4["x"][1] == 123.4);

   // Unorthodox formatting
   auto v5 = parseConfig("
     x
     = {     'abc'
       ,false,
       --1.5,
       5.1--howdy!}
     }--} ");
   assert(v5["x"].isList);
   assert(v5["x"].length == 3);
   assert(v5["x"][0] == "abc");
   assert(v5["x"][1] == false);
   assert(v5["x"][2] == 5.1);
}

/// More tests with associative arrays
unittest
{
   // No trailing comma, one element
   auto v1 = parseConfig("aa = { x = 'abc' } ");
   assert(v1["aa"].isAA);
   assert(v1["aa"].length == 1);
   assert(v1["aa"]["x"] == "abc");

   // Trailing comma, one element
   auto v2 = parseConfig("aa = { x = 'abc', } ");
   assert(v2["aa"].isAA);
   assert(v2["aa"].length == 1);
   assert(v2["aa"]["x"] == "abc");

   // No trailing comma, multiple elements
   auto v3 = parseConfig("aa = { x = 'abc', y = 123.4 } ");
   assert(v3["aa"].isAA);
   assert(v3["aa"].length == 2);
   assert(v3["aa"]["x"] == "abc");
   assert(v3["aa"]["y"] == 123.4);

   // Trailing comma, multiple elements
   auto v4 = parseConfig("aa = { x = 'abc', y = 123.4, } ");
   assert(v4["aa"].isAA);
   assert(v4["aa"].length == 2);
   assert(v4["aa"]["x"] == "abc");
   assert(v4["aa"]["y"] == 123.4);

   // Unorthodox formatting
   auto v5 = parseConfig("
     aa
     = {     x = --\"xxx'
       'abc'
       ,y=123.4,
       --1.5,
       z             =
       true--howdy!}
     }--} ");
   assert(v5["aa"].isAA);
   assert(v5["aa"].length == 3);
   assert(v5["aa"]["x"] == "abc");
   assert(v5["aa"]["y"] == 123.4);
   assert(v5["aa"]["z"] == true);
}

/// Try some comments and blanks
unittest
{
   auto value = parseConfig(`
      -- This is a comment
      -- This is still a comment
      a = 9.8 -- a comment
      b =          8.7

      c = 7.6--more comment...--
      -- d = 6.5
   `);

   assert(value.isAA);
   assert(value.length == 3);
   assert("a" in value.asAA);
   assert("b" in value.asAA);
   assert("c" in value.asAA);
   assert("d" !in value.asAA);
   assert(value["a"] == 9.8);
   assert(value["b"] == 8.7);
   assert(value["c"] == 7.6);
}

/// Nested data structures, simple case
unittest
{
   auto v = parseConfig(
      "aa = {
          seq = {1,2,3},
          nestedAA = { foo = 'bar' }} ");

   assert(v["aa"].isAA);
   assert(v["aa"].length == 2);

   assert(v["aa"]["seq"].isList);
   assert(v["aa"]["seq"].length == 3);
   assert(v["aa"]["seq"][0] == 1);
   assert(v["aa"]["seq"][1] == 2);
   assert(v["aa"]["seq"][2] == 3);

   assert(v["aa"]["nestedAA"].isAA);
   assert(v["aa"]["nestedAA"].length == 1);
   assert("foo" in v["aa"]["nestedAA"].asAA);
   assert(v["aa"]["nestedAA"]["foo"] == "bar");
}

/// Nested data structures, more complex case
unittest
{
   auto v = parseConfig(
      "aa = {
          seq = {1, { 2, 'two' } ,3},
          nestedAA = { foo = 'bar', baz = { oneMore = 'enough' } }
      }

      list = {
                nil,
                { 'a', 'b', -11.1, },
                { x = '0', y = 0, z = { 0 }, },
                false,
             }
 ");

   assert(v["aa"].isAA);
   assert(v["aa"].length == 2);

   assert(v["aa"]["seq"].isList);
   assert(v["aa"]["seq"].length == 3);
   assert(v["aa"]["seq"][0] == 1);
   assert(v["aa"]["seq"][2] == 3);
   assert(v["aa"]["seq"][1].isList);
   assert(v["aa"]["seq"][1].length == 2);
   assert(v["aa"]["seq"][1][0] == 2);
   assert(v["aa"]["seq"][1][1] == "two");

   assert(v["aa"]["nestedAA"].isAA);
   assert(v["aa"]["nestedAA"].length == 2);
   assert("foo" in v["aa"]["nestedAA"].asAA);
   assert(v["aa"]["nestedAA"]["foo"] == "bar");
   assert("baz" in v["aa"]["nestedAA"].asAA);
   assert(v["aa"]["nestedAA"]["baz"].isAA);
   assert(v["aa"]["nestedAA"]["baz"].length == 1);
   assert("oneMore" in v["aa"]["nestedAA"]["baz"].asAA);
   assert(v["aa"]["nestedAA"]["baz"]["oneMore"] == "enough");

   assert(v["list"].isList);
   assert(v["list"].length == 4);

   assert(v["list"][0].isNil);

   assert(v["list"][1].isList);
   assert(v["list"][1].length == 3);
   assert(v["list"][1][0] == "a");
   assert(v["list"][1][1] == "b");
   assert(v["list"][1][2] == -11.1);

   assert(v["list"][2].isAA);
   assert(v["list"][2].length == 3);
   assert(v["list"][2]["x"] == "0");
   assert(v["list"][2]["y"] == 0);
   assert(v["list"][2]["z"].isList);
   assert(v["list"][2]["z"].length == 1);
   assert(v["list"][2]["z"][0] == 0);

   assert(v["list"][3].isBoolean);
   assert(v["list"][3] == false);
}

// Test if this really works at compile-time.
unittest
{
   double fun(string data)
   {
      auto v = parseConfig(data);
      return v["u_u"]["foo"][1].asNumber;
   }

   enum val = fun("u_u = { foo = { nil, 4, 'foo', -3e-2}, bar = 627.478} ----");
   assert(val == 4);
}

// Creating 'ConfigValue's from code
unittest
{
   ConfigValue c;

   // Number, simple case
   c = 2.345;
   assert(c.isNumber);
   assert(c == 2.345);

   // Numbers that used to be interpreted as Booleans
   c = 1;
   assert(c.isNumber);
   assert(c == 1);

   c = 0;
   assert(c.isNumber);
   assert(c == 0);

   // String
   c = "hello";
   assert(c.isString);
   assert(c == "hello");

   // Boolean
   c = true;
   assert(c.isBoolean);
   assert(c == true);

   // Associative array
   ConfigValue[string] aa;
   aa["x"] = 1;
   aa["y"] = "yay!";
   aa["z"] = false;

   c = aa;
   assert(c.isAA);
   assert(c.length == 3);
   assert(c["x"] == 1);
   assert(c["y"] == "yay!");
   assert(c["z"] == false);

   // List
   ConfigValue[] list =
      [ ConfigValue(-8.2), ConfigValue(true), ConfigValue("bab!") ];
   c = list;
   assert(c.isList);
   assert(c.length == 3);
   assert(c[0] == -8.2);
   assert(c[1] == true);
   assert(c[2] == "bab!");
}

// Creating 'ConfigValue's from code, emphasis on list
unittest
{
   ConfigValue c;
   c.makeList();

   c[0] = -987.6;
   c[1] = true;
   c[2] = "abc";

   assert(c.isList);
   assert(c.length == 3);
   assert(c[0] == -987.6);
   assert(c[1] == true);
   assert(c[2] == "abc");
}

// Creating 'ConfigValue's from code, emphasis on associative array
unittest
{
   ConfigValue c;
   c.makeAA();

   c["A"] = -987.6;
   c["b"] = true;
   c["cee"] = "abc";

   assert(c.isAA);
   assert(c.length == 3);
   assert(c["A"] == -987.6);
   assert(c["b"] == true);
   assert(c["cee"] == "abc");
}


/**
 * Converts a $(D ConfigValue) to its string representation.
 *
 * Actually, this doesn't work with any $(D ConfigValue); this works only with
 * associative arrays, and the key/value pairs are converted to top-level
 * assignments. In other words, this does the inverse of $(D parseConfig()).
 *
 * Parameters:
 *    data = The value to convert to a string. Must be an associative array.
 *    prettyPrint = Add line breaks and indentation to make the string easier to
 *       be read by human beings? If not, the returned string will be more
 *       compact.
 *
 * Returns:
 *    $(D value), represented as a string of Lua-like code.
 */
public string stringify(const ConfigValue value, bool prettyPrint = true)
in
{
   assert(value.isAA);
}
body
{
   string doStringify(const ConfigValue value, int indentLevel)
   {
      string indentString(int level)
      in
      {
         assert(level >= 0);
      }
      body
      {
         string res = "";
         foreach (i; 0..level)
            res ~= "   ";
         return res;
      }

      auto nl = prettyPrint ? "\n" : "";
      auto inThis = prettyPrint ? indentString(indentLevel) : "";
      auto inPrev = prettyPrint ? indentString(indentLevel-1) : "";
      auto space = prettyPrint ? " " : "";

      final switch(value.type)
      {
         case ConfigValueType.NIL:
            return "nil";

         case ConfigValueType.NUMBER:
            return to!string(value.asNumber);

         case ConfigValueType.STRING:
         {
            return `"`
               ~ value.asString
               .replace("\\", "\\\\")
               .replace("\n", "\\n")
               .replace("\'", "\\\'")
               .replace("\"", "\\\"")
               ~ `"`;
         }

         case ConfigValueType.BOOLEAN:
            return value.asBoolean ? "true" : "false";

         case ConfigValueType.AA:
         {
            string res = "{" ~ nl;
            foreach (k, v; value.asAA)
            {
               res ~= inThis ~ k ~ space ~ "=" ~ space
                  ~ doStringify(v, indentLevel + 1) ~ "," ~ nl;
            }

            return res ~ inPrev ~ "}";
         }

         case ConfigValueType.LIST:
         {
            string res = "{" ~ nl;
            foreach (v; value.asList)
               res ~= inThis ~ doStringify(v, indentLevel + 1) ~ "," ~ nl;

            return res ~ inPrev ~ "}";
         }
      }
   }

   string res = "";

   auto len = value.length;
   auto i = 0;
   foreach (k, v; value.asAA)
      res ~= k ~ " = " ~ doStringify(v, 1) ~ "\n";

   return res;
}


// stringify: simple cases
unittest
{
   ConfigValue origCV;
   origCV.makeAA();
   origCV["aNil"] = ConfigValue();
   origCV["aNumber"] = ConfigValue(-756.342);
   origCV["aString"] = ConfigValue("Beep!");
   origCV["aBoolean"] = ConfigValue(true);

   ConfigValue[string] theAA;
   theAA["x"] = 1;
   theAA["y"] = "yay!";
   theAA["z"] = false;

   origCV["anAA"] = ConfigValue(theAA);

   auto theList = [ ConfigValue(-8.2), ConfigValue(true), ConfigValue("bab!") ];
   origCV["aList"] = ConfigValue(theList);

   // Pretty
   {
      string s = origCV.stringify(true);
      auto cv = parseConfig(s);

      assert(cv.isAA);
      assert(cv.length == 6);
      assert("aNil" in cv.asAA);
      assert("aNumber" in cv.asAA);
      assert("aString" in cv.asAA);
      assert("aBoolean" in cv.asAA);
      assert("anAA" in cv.asAA);
      assert("aList" in cv.asAA);

      assert(cv["aNil"].isNil);
      assert(cv["aNumber"] == -756.342);
      assert(cv["aString"] == "Beep!");
      assert(cv["aBoolean"] == true);

      assert(cv["anAA"].isAA);
      assert(cv["anAA"].length == 3);
      assert("x" in cv["anAA"].asAA);
      assert("y" in cv["anAA"].asAA);
      assert("z" in cv["anAA"].asAA);
      assert(cv["anAA"]["x"] == 1);
      assert(cv["anAA"]["y"] == "yay!");
      assert(cv["anAA"]["z"] == false);

      assert(cv["aList"].isList);
      assert(cv["aList"].length == 3);
      assert(cv["aList"][0] == -8.2);
      assert(cv["aList"][1] == true);
      assert(cv["aList"][2] == "bab!");
   }

   // Ugly
   {
      string s = origCV.stringify(false);
      auto cv = parseConfig(s);

      assert(cv.isAA);
      assert(cv.length == 6);
      assert("aNil" in cv.asAA);
      assert("aNumber" in cv.asAA);
      assert("aString" in cv.asAA);
      assert("aBoolean" in cv.asAA);
      assert("anAA" in cv.asAA);
      assert("aList" in cv.asAA);

      assert(cv["aNil"].isNil);
      assert(cv["aNumber"] == -756.342);
      assert(cv["aString"] == "Beep!");
      assert(cv["aBoolean"] == true);

      assert(cv["anAA"].isAA);
      assert(cv["anAA"].length == 3);
      assert("x" in cv["anAA"].asAA);
      assert("y" in cv["anAA"].asAA);
      assert("z" in cv["anAA"].asAA);
      assert(cv["anAA"]["x"] == 1);
      assert(cv["anAA"]["y"] == "yay!");
      assert(cv["anAA"]["z"] == false);

      assert(cv["aList"].isList);
      assert(cv["aList"].length == 3);
      assert(cv["aList"][0] == -8.2);
      assert(cv["aList"][1] == true);
      assert(cv["aList"][2] == "bab!");
   }
}

// stringify: string with escaped characters
unittest
{
   enum theString = `First 'quoted" line
Second line \ contains a backslash!`;
   ConfigValue origCV;
   origCV.makeAA();
   origCV["s"] = theString;

   // Pretty
   {
      string s = origCV.stringify(true);
      auto cv = parseConfig(s);
      assert(cv["s"].asString == theString);
   }

   // Ugly
   {
      string s = origCV.stringify(false);
      auto cv = parseConfig(s);
      assert(cv["s"].asString == theString);
   }
}

// stringify: more complex case
unittest
{
   ConfigValue[string] yetAnotherAA;
   yetAnotherAA["a"] = true;
   yetAnotherAA["b"] = -1.001;
   yetAnotherAA["c"] = ConfigValue();

   ConfigValue[string] anotherAA;
   anotherAA["foo"] = "FOO";
   anotherAA["bar"] = yetAnotherAA;
   anotherAA["baz"] = 645;

   ConfigValue[string] rootAA;
   rootAA["aNumber"] = -0.1234;
   rootAA["aList"] = ConfigValue([ ConfigValue(1.1), ConfigValue("true") ]);
   rootAA["anotherAA"] = anotherAA;

   auto cv = ConfigValue(rootAA);

   string prettyString = cv.stringify(true);
   string uglyString = cv.stringify(false);

   // Pretty
   auto prettyCV = parseConfig(prettyString);
   assert(prettyCV.isAA);
   assert(prettyCV.length == 3);

   assert("aNumber" in prettyCV.asAA);
   assert(prettyCV["aNumber"] == -0.1234);

   assert("aList" in prettyCV.asAA);
   assert(prettyCV["aList"].isList);
   assert(prettyCV["aList"].length == 2);
   assert(prettyCV["aList"][0] == 1.1);
   assert(prettyCV["aList"][1] == "true");

   assert("anotherAA" in prettyCV.asAA);
   assert(prettyCV["anotherAA"].isAA);
   assert(prettyCV["anotherAA"].length == 3);

   assert("foo" in prettyCV["anotherAA"].asAA);
   assert(prettyCV["anotherAA"]["foo"] == "FOO");

   assert("bar" in prettyCV["anotherAA"].asAA);
   assert(prettyCV["anotherAA"]["bar"].isAA);
   assert(prettyCV["anotherAA"]["bar"].length == 3);
   assert("a" in prettyCV["anotherAA"]["bar"].asAA);
   assert(prettyCV["anotherAA"]["bar"]["a"] == true);
   assert("b" in prettyCV["anotherAA"]["bar"].asAA);
   assert(prettyCV["anotherAA"]["bar"]["b"] == -1.001);
   assert("c" in prettyCV["anotherAA"]["bar"].asAA);
   assert(prettyCV["anotherAA"]["bar"]["c"].isNil);

   assert("baz" in prettyCV["anotherAA"].asAA);
   assert(prettyCV["anotherAA"]["baz"] = 645);

   // Ugly
   auto uglyCV = parseConfig(uglyString);
   assert(uglyCV.isAA);
   assert(uglyCV.length == 3);

   assert("aNumber" in uglyCV.asAA);
   assert(uglyCV["aNumber"] == -0.1234);

   assert("aList" in uglyCV.asAA);
   assert(uglyCV["aList"].isList);
   assert(uglyCV["aList"].length == 2);
   assert(uglyCV["aList"][0] == 1.1);
   assert(uglyCV["aList"][1] == "true");

   assert("anotherAA" in uglyCV.asAA);
   assert(uglyCV["anotherAA"].isAA);
   assert(uglyCV["anotherAA"].length == 3);

   assert("foo" in uglyCV["anotherAA"].asAA);
   assert(uglyCV["anotherAA"]["foo"] == "FOO");

   assert("bar" in uglyCV["anotherAA"].asAA);
   assert(uglyCV["anotherAA"]["bar"].isAA);
   assert(uglyCV["anotherAA"]["bar"].length == 3);
   assert("a" in uglyCV["anotherAA"]["bar"].asAA);
   assert(uglyCV["anotherAA"]["bar"]["a"] == true);
   assert("b" in uglyCV["anotherAA"]["bar"].asAA);
   assert(uglyCV["anotherAA"]["bar"]["b"] == -1.001);
   assert("c" in uglyCV["anotherAA"]["bar"].asAA);
   assert(uglyCV["anotherAA"]["bar"]["c"].isNil);

   assert("baz" in uglyCV["anotherAA"].asAA);
   assert(uglyCV["anotherAA"]["baz"] == 645);
}
