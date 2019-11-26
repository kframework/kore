{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

 -}

module Kore.Builtin.Signedness
    ( verifiers
    , signedKey
    , unsignedKey
    , unifyEquals
    , module Kore.Builtin.Signedness.Signedness
    ) where

import Control.Applicative
    ( Alternative (..)
    )
import Control.Error
    ( MaybeT
    )
import qualified Control.Monad as Monad
import qualified Control.Monad.Trans as Trans
import Data.Functor.Const
import qualified Data.HashMap.Strict as HashMap
import Data.String
    ( IsString
    )

import qualified Kore.Attribute.Symbol as Attribute.Symbol
import Kore.Builtin.Builtin
import Kore.Builtin.Signedness.Signedness
import Kore.Error
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Symbol
import Kore.Internal.TermLike
import Kore.Step.Simplification.Simplify
    ( SimplifierVariable
    )
import Kore.Syntax.Application
    ( Application (..)
    )
import Kore.Unification.Unify
    ( MonadUnify
    , explainAndReturnBottom
    )
import qualified Kore.Verified as Verified

verifiers :: Verifiers
verifiers =
    mempty
        { patternVerifier =
            (applicationPatternVerifiers . HashMap.fromList)
                [ (KlabelSymbolKey signedKey  , signedVerifier  )
                , (KlabelSymbolKey unsignedKey, unsignedVerifier)
                ]
        }

signedKey :: IsString str => str
signedKey = "signedBytes"

unsignedKey :: IsString str => str
unsignedKey = "unsignedBytes"

signednessVerifier
    :: (Symbol -> Signedness)  -- ^ Constructor
    -> ApplicationVerifier Verified.Pattern
signednessVerifier ctor =
    ApplicationVerifier worker
  where
    worker application = do
        -- TODO (thomas.tuegel): Move the checks into the symbol verifiers.
        Monad.unless (null arguments)
            (koreFail "expected zero arguments")
        let Attribute.Symbol.SymbolKywd { isSymbolKywd } =
                Attribute.Symbol.symbolKywd $ symbolAttributes symbol
        Monad.unless isSymbolKywd
            (koreFail "expected symbol'Kywd'{}() attribute")
        return (SignednessF . Const $ ctor symbol)
      where
        arguments = applicationChildren application
        symbol = applicationSymbolOrAlias application

signedVerifier :: ApplicationVerifier Verified.Pattern
signedVerifier = signednessVerifier Signed

unsignedVerifier :: ApplicationVerifier Verified.Pattern
unsignedVerifier = signednessVerifier Unsigned

unifyEquals
    :: SimplifierVariable variable
    => MonadUnify unifier
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
unifyEquals termLike1@(Signedness_ sign1) termLike2@(Signedness_ sign2)
  | sign1 == sign2 = return (Pattern.fromTermLike termLike1)
  | otherwise =
    Trans.lift $ explainAndReturnBottom
        "Cannot unify distinct constructors."
        termLike1
        termLike2
unifyEquals _ _ = empty
