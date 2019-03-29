{-|
Module      : Kore.Repl.Parser
Description : REPL parser.
Copyright   : (c) Runtime Verification, 219
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
-}

module Kore.Repl.Parser
    ( commandParser
    ) where

import Text.Megaparsec
       ( Parsec, option, optional, (<|>) )
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer
       ( decimal )

import Kore.Repl.Data
       ( ReplCommand (..) )

type Parser = Parsec String String

-- | This parser fails no match is found. It is expected to be used as
-- @
-- maybe ShowUsage id . Text.Megaparsec.parseMaybe commandParser
-- @
commandParser :: Parser ReplCommand
commandParser =
    help
    <|> showClaim
    <|> showAxiom
    <|> prove
    <|> showGraph
    <|> proveSteps
    <|> selectNode
    <|> showConfig
    <|> showLeafs
    <|> showPrecBranch
    <|> showChildren
    <|> exit

help :: Parser ReplCommand
help = Help <$ (string "help" *> space)

showClaim :: Parser ReplCommand
showClaim = fmap ShowClaim $ string "claim" *> space *> decimal <* space

showAxiom :: Parser ReplCommand
showAxiom = fmap ShowAxiom $ string "axiom" *> space *> decimal <* space

prove :: Parser ReplCommand
prove = fmap Prove $ string "prove" *> space *> decimal <* space

showGraph :: Parser ReplCommand
showGraph = ShowGraph <$ (string "graph" *> space)

proveSteps :: Parser ReplCommand
proveSteps =
    fmap ProveSteps $ string "step" *> space *> option 1 decimal <* space

selectNode :: Parser ReplCommand
selectNode =
    fmap SelectNode $ string "select" *> space *> decimal <* space

showConfig :: Parser ReplCommand
showConfig =
    fmap ShowConfig $ string "config" *> space *> optional decimal <* space

showLeafs :: Parser ReplCommand
showLeafs = ShowLeafs <$ (string "leafs" *> space)

showPrecBranch :: Parser ReplCommand
showPrecBranch =
    fmap ShowPrecBranch $ string "prec-branch" *> space *> optional decimal <* space

showChildren :: Parser ReplCommand
showChildren =
    fmap ShowChildren $ string "children" *> space *> optional decimal <* space

exit :: Parser ReplCommand
exit = Exit <$ (string "exit" *> space)
