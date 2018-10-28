{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module Example.QQ where

import Control.Monad (void)
import Data.Char (isUpper, isAlpha, isAlphaNum, isNumber)
import Data.Foldable (traverse_)
import Data.Text (Text)
import Language.Haskell.Meta (toExp)
import Language.Haskell.TH (ExpQ, reify, pprint, runIO)
import Language.Haskell.TH.Quote (QuasiQuoter(..))
import Language.Haskell.TH.Syntax (Name)
import Reflex.Dom.SemanticUI hiding (parseType)

import qualified Data.Text as T
import qualified Language.Haskell.Exts as Exts
import qualified Language.Haskell.HsColour.Classify as HsColour

mymode :: Exts.ParseMode
mymode = Exts.defaultParseMode
    { Exts.baseLanguage = Exts.Haskell2010
    , Exts.fixities = Just $ Exts.preludeFixities
                          ++ Exts.baseFixities
                          ++ Exts.infixl_ 8 ["^?", "^."]
                          ++ Exts.infixr_ 4 ["%~", ".~", "?~", "|~", "|?~"]
                          ++ Exts.infixl_ 1 ["&"]
    , Exts.extensions = Exts.EnableExtension <$> exts
    }

exts :: [Exts.KnownExtension]
exts
  = [ Exts.ExistentialQuantification
  , Exts.TypeFamilies
  , Exts.TypeApplications
  , Exts.ExplicitForAll
  , Exts.DataKinds
  , Exts.LambdaCase
  , Exts.GADTs
  , Exts.MultiParamTypeClasses
  , Exts.RecordWildCards
  , Exts.RecursiveDo
  , Exts.ScopedTypeVariables
  ]

-- | Pretty print the definition of a haskell type
printDefinition :: (String -> String) -> (String -> String) -> Name -> ExpQ
printDefinition postproc preproc name = do
  info <- reify name
  let
    mode = Exts.defaultParseMode
      { Exts.baseLanguage = Exts.Haskell2010
      , Exts.extensions = Exts.EnableExtension <$> exts
      }
    style' = Exts.style { Exts.lineLength = 9999, Exts.ribbonsPerLine = 1 }
    parse = Exts.parseDeclWithMode mode . stripForAll . stripTypes . stripNumbers . stripModules . preproc . pprint
    prettyPrint = postproc . newlines . Exts.prettyPrintStyleMode style' Exts.defaultMode
    pp = prettyPrint . Exts.fromParseResult . parse $ info
  case parse info of
    Exts.ParseOk _ -> [|pp|]
    Exts.ParseFailed loc str' -> do
      runIO $ print loc
      runIO $ putStrLn $ stripModules $ pprint info
      fail str'

hscode :: UI t m => String -> m ()
hscode = void . elAttr "code" ("class" =: "haskell")
       . el "pre" . hscolour

hsCodeInline :: UI t m => String -> m ()
hsCodeInline = void . elAttr "code" ("class" =: "haskell inline")
             . el "pre" . hscolour

hscolour :: DomBuilder t m => String -> m ()
hscolour = traverse_ renderToken' . HsColour.tokenise . unindent

renderToken' :: DomBuilder t m => (HsColour.TokenType,String) -> m ()
renderToken' (cls,s) = elClass "span" (cssClass cls) $ text $ T.pack s

cssClass :: HsColour.TokenType -> Text
cssClass HsColour.Keyword  = "hs-keyword"
cssClass HsColour.Keyglyph = "hs-keyglyph"
cssClass HsColour.Layout   = "hs-layout"
cssClass HsColour.Comment  = "hs-comment"
cssClass HsColour.Conid    = "hs-conid"
cssClass HsColour.Varid    = "hs-varid"
cssClass HsColour.Conop    = "hs-conop"
cssClass HsColour.Varop    = "hs-varop"
cssClass HsColour.String   = "hs-str"
cssClass HsColour.Char     = "hs-chr"
cssClass HsColour.Number   = "hs-num"
cssClass HsColour.Cpp      = "hs-cpp"
cssClass HsColour.Error    = "hs-sel"
cssClass HsColour.Definition = "hs-definition"
cssClass _        = ""

oneline :: String -> String
oneline "" = ""
oneline ('\n':rest) = oneline rest
oneline (' ':rest) = ' ' : oneline (dropWhile (==' ') rest)
oneline (x:rest) = x : oneline rest

newlines :: String -> String
newlines "" = ""
newlines ('{':' ':rest) = "\n  { " ++ newlines rest
newlines ('{':rest) = "\n  { " ++ newlines rest
newlines ('}':rest) = "\n  }" ++ newlines rest
newlines (',':rest) = "\n  ," ++ newlines rest
newlines (x:rest) = x : newlines rest

stripForAll :: String -> String
stripForAll "" = ""
stripForAll ('f':'o':'r':'a':'l':'l':rest) = stripForAll $ drop 1 $ dropWhile (/= '.') rest
stripForAll (x:rest) = x : stripForAll rest

-- Breaks stuff
stripParens :: String -> String
stripParens "" = ""
stripParens ('-':'>':' ':'(':rest) = '-':'>':' ': stripParens rest
stripParens ('=':'>':' ':'(':rest) = '=':'>':' ': stripParens rest
stripParens (':':':':' ':'(':rest) = ':':':':' ': stripParens rest
stripParens (')':',':rest) = ',': stripParens rest
stripParens (')':'}':rest) = '}': stripParens rest
stripParens (')':' ':'-':'>':rest) = stripParens $ ' ':'-':'>': rest
stripParens (x:rest) = x : stripParens rest

stripModules :: String -> String
stripModules "" = ""
stripModules (c:s)
  | isUpper c = case span isAlpha (c:s) of
    (_, '.':rest) -> stripModules rest
    (taken, rest) -> taken ++ stripModules rest
  | otherwise = c : stripModules s

stripNumbers :: String -> String
stripNumbers "" = ""
stripNumbers (x:'_':a:b:c:rest)
  | isAlphaNum x && isNumber a && isNumber b && isNumber c = x : stripNumbers rest
stripNumbers (x:'_':a:b:rest)
  | isAlphaNum x && isNumber a && isNumber b = x : stripNumbers rest
stripNumbers (x:'_':a:rest)
  | isAlphaNum x && isNumber a = x : stripNumbers rest
stripNumbers (x:rest) = x : stripNumbers rest

stripTypes :: String -> String
stripTypes "" = ""
stripTypes ('(':t:' ':':':':':' ':rest)
  | isAlpha t = t:' ': stripTypes (drop 1 $ dropWhile (/= ')') rest)
stripTypes ('(':t:a:' ':':':':':' ':rest)
  | isAlpha t && isAlphaNum a = t:a:' ': stripTypes (drop 1 $ dropWhile (/= ')') rest)
stripTypes (x:rest) = x : stripTypes rest

-- | Strips indentation spaces from a string
unindent :: String -> String
unindent s = unlines $ map (drop $ minSpaces loc) loc
  where loc = lines s

-- | Counts the smallest number of spaces that any string in the list is
-- indented by
minSpaces :: [String] -> Int
minSpaces = minimum . map (length . takeWhile (== ' ')) . filter (/= "")

example :: QuasiQuoter
example = QuasiQuoter
  { quoteExp = \ex -> [|(ex, $(return $ toExp $ Exts.fromParseResult $ Exts.parseExpWithMode mymode $ "Left $ do\n" ++ ex))|]
  , quotePat = const $ error "ex: not an expression"
  , quoteType = const $ error "ex: not an expression"
  , quoteDec = const $ error "ex: not an expression"
  }

resetExample :: QuasiQuoter
resetExample = example { quoteExp = \ex -> [|(ex, $(return $ toExp $ Exts.fromParseResult $ Exts.parseExpWithMode mymode $ "Right $ do\n" ++ ex))|] }

str :: QuasiQuoter
str = example
  { quoteExp = \ex -> [|ex|] }

