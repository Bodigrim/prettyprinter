{-# LANGUAGE CPP               #-}
{-# LANGUAGE LinearTypes       #-}
{-# LANGUAGE UnicodeSyntax     #-}
{-# LANGUAGE BangPatterns      #-}

#include "version-compatibility-macros.h"

-- | Render an unannotated 'SimpleDocStream' as plain 'Text'.
module Prettyprinter.Render.Text (
#ifdef MIN_VERSION_text
    -- * Conversion to plain 'Text'
    renderLazy, renderStrict,
#endif

    -- * Render to a 'Handle'
    renderIO,

    -- ** Convenience functions
    putDoc, hPutDoc
) where



import           Data.Text              (Text)
import qualified Data.Text.IO           as T
import qualified Data.Text.Lazy         as TL
import qualified Data.Text.Lazy.Builder as TLB
import           System.IO

import Prettyprinter
import Prettyprinter.Internal
import Prettyprinter.Render.Util.Panic

#if !(SEMIGROUP_IN_BASE)
import Data.Semigroup
#endif

#if !(APPLICATIVE_MONAD)
import Control.Applicative
#endif

import Data.Text.Builder.Linear.Buffer

-- $setup
--
-- (Definitions for the doctests)
--
-- >>> :set -XOverloadedStrings
-- >>> import qualified Data.Text.IO as T
-- >>> import qualified Data.Text.Lazy.IO as TL



-- | @('renderLazy' sdoc)@ takes the output @sdoc@ from a rendering function
-- and transforms it to lazy text.
--
-- >>> let render = TL.putStrLn . renderLazy . layoutPretty defaultLayoutOptions
-- >>> let doc = "lorem" <+> align (vsep ["ipsum dolor", parens "foo bar", "sit amet"])
-- >>> render doc
-- lorem ipsum dolor
--       (foo bar)
--       sit amet
renderLazy :: SimpleDocStream ann -> TL.Text
renderLazy = TLB.toLazyText . go
  where
    go x = case x of
        SFail              -> panicUncaughtFail
        SEmpty             -> mempty
        SChar c rest       -> TLB.singleton c <> go rest
        SText _l t rest    -> TLB.fromText t <> go rest
        SLine i rest       -> TLB.singleton '\n' <> (TLB.fromText (textSpaces i) <> go rest)
        SAnnPush _ann rest -> go rest
        SAnnPop rest       -> go rest

-- | @('renderStrict' sdoc)@ takes the output @sdoc@ from a rendering function
-- and transforms it to strict text.
renderStrict :: SimpleDocStream ann -> Text
renderStrict sdc = runBuffer (\b -> (go b sdc))
  where
    go :: Buffer ⊸ SimpleDocStream ann -> Buffer
    go !b !sbc = case sbc of
      SFail -> undefined b
      SEmpty -> b
      SChar c rest -> go (b |>. c) rest
      SText _l t rest -> go (b |> t) rest
      SLine i rest -> go ((b |>. '\n') |>… fromIntegral i) rest
      SAnnPush _ann rest -> go b rest
      SAnnPop rest -> go b rest

-- | @('renderIO' h sdoc)@ writes @sdoc@ to the file @h@.
--
-- >>> renderIO System.IO.stdout (layoutPretty defaultLayoutOptions "hello\nworld")
-- hello
-- world
--
-- This function is more efficient than @'T.hPutStr' h ('renderStrict' sdoc)@,
-- since it writes to the handle directly, skipping the intermediate 'Text'
-- representation.
renderIO :: Handle -> SimpleDocStream ann -> IO ()
renderIO h = go
  where
    go :: SimpleDocStream ann -> IO ()
    go = \sds -> case sds of
        SFail              -> panicUncaughtFail
        SEmpty             -> pure ()
        SChar c rest       -> do hPutChar h c
                                 go rest
        SText _ t rest     -> do T.hPutStr h t
                                 go rest
        SLine n rest       -> do hPutChar h '\n'
                                 T.hPutStr h (textSpaces n)
                                 go rest
        SAnnPush _ann rest -> go rest
        SAnnPop rest       -> go rest

-- | @('putDoc' doc)@ prettyprints document @doc@ to standard output. Uses the
-- 'defaultLayoutOptions'.
--
-- >>> putDoc ("hello" <+> "world")
-- hello world
--
-- @
-- 'putDoc' = 'hPutDoc' 'stdout'
-- @
putDoc :: Doc ann -> IO ()
putDoc = hPutDoc stdout

-- | Like 'putDoc', but instead of using 'stdout', print to a user-provided
-- handle, e.g. a file or a socket. Uses the 'defaultLayoutOptions'.
--
-- @
-- main = 'withFile' filename (\h -> 'hPutDoc' h doc)
--   where
--     doc = 'vcat' ["vertical", "text"]
--     filename = "someFile.txt"
-- @
--
-- @
-- 'hPutDoc' h doc = 'renderIO' h ('layoutPretty' 'defaultLayoutOptions' doc)
-- @
hPutDoc :: Handle -> Doc ann -> IO ()
hPutDoc h doc = renderIO h (layoutPretty defaultLayoutOptions doc)
