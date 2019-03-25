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
       ( decimal, signed )

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
    <|> exit

help :: Parser ReplCommand
help = Help <$ string "help"

showClaim :: Parser ReplCommand
showClaim = fmap ShowClaim $ string "claim" *> space *> decimal

showAxiom :: Parser ReplCommand
showAxiom = fmap ShowAxiom $ string "axiom" *> space *> decimal

prove :: Parser ReplCommand
prove = fmap Prove $ string "prove" *> space *> decimal

showGraph :: Parser ReplCommand
showGraph = ShowGraph <$ string "graph"

proveSteps :: Parser ReplCommand
proveSteps = fmap ProveSteps $ string "step" *> space *> option 1 decimal

selectNode :: Parser ReplCommand
selectNode = fmap SelectNode $ string "select" *> space *> signed space decimal

showConfig :: Parser ReplCommand
showConfig = fmap ShowConfig $ string "config" *> optional (space *> decimal)

exit :: Parser ReplCommand
exit = Exit <$ string "exit"
