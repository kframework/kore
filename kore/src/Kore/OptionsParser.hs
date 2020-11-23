module Kore.OptionsParser
    ( enableDisableFlag
    , KoreParserOptions (..)
    , commandLineParser
    ) where

import Data.Text
    ( Text
    )

import Prelude.Kore

import Options.Applicative

{-|
Parser builder to create an optional boolean flag,
with an enabled, disabled and default value.
Based on `enableDisableFlagNoDefault`
from commercialhaskell/stack:
https://github.com/commercialhaskell/stack/blob/master/src/Options/Applicative/Builder/Extra.hs
-}
enableDisableFlag
    :: String -- ^ flag name
    -> option -- ^ enabled value
    -> option -- ^ disabled value
    -> option -- ^ default value
    -> String -- ^ Help text suffix; appended to "Enable/disable "
    -> Parser option
enableDisableFlag name enabledVal disabledVal defaultVal helpSuffix =
    flag' enabledVal
        (  hidden
        <> internal
        <> long name
        <> help helpSuffix)
    <|> flag' disabledVal
        (  hidden
        <> internal
        <> long ("no-" ++ name)
        <> help helpSuffix )
    <|> flag' disabledVal
        (  long ( "[no-]" ++ name )
        <> help ( "Enable/disable " ++ helpSuffix ) )
    <|> pure defaultVal

-- | Main options record
data KoreParserOptions = KoreParserOptions
    { fileName            :: !FilePath
    -- ^ Name for a file containing a definition to parse and verify
    , patternFileName     :: !FilePath
    -- ^ Name for file containing a pattern to parse and verify
    , mainModuleName      :: !Text
    -- ^ the name of the main module in the definition
    , willPrintDefinition :: !Bool
    -- ^ Option to print definition
    , willPrintPattern    :: !Bool
    -- ^ Option to print pattern
    , willVerify          :: !Bool
    -- ^ Option to verify definition
    , appKore             :: !Bool
    -- ^ Option to print in applicative Kore syntax
    }

-- | Command Line Argument Parser
commandLineParser :: Parser KoreParserOptions
commandLineParser =
    KoreParserOptions
    <$> argument str
        (  metavar "FILE"
        <> help "Kore source file to parse [and verify]" )
    <*> strOption
        (  metavar "PATTERN_FILE"
        <> long "pattern"
        <> help
            "Kore pattern source file to parse [and verify]. Needs --module."
        <> value "" )
    <*> strOption
        (  metavar "MODULE"
        <> long "module"
        <> help "The name of the main module in the Kore definition"
        <> value "" )
    <*> enableDisableFlag "print-definition"
        True False False
        "printing parsed definition to stdout [default disabled]"
    <*> enableDisableFlag "print-pattern"
        True False False
        "printing parsed pattern to stdout [default disabled]"
    <*> enableDisableFlag "verify"
        True False True
        "Verify well-formedness of parsed definition [default enabled]"
    <*> enableDisableFlag "appkore"
        True False False
        (  "printing parsed definition in applicative Kore syntax "
        ++ "[default disabled]"
        )
