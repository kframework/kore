{- |
Module      : Kore.Builtin.String
Description : Built-in string sort
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
Stability   : experimental
Portability : portable

This module is intended to be imported qualified, to avoid collision with other
builtin modules.

@
    import qualified Kore.Builtin.String as String
@
 -}

module Kore.Builtin.String
    ( sort
    , assertSort
    , verifiers
    , builtinFunctions
    , expectBuiltinString
    , asInternal
    , asPattern
    , asTermLike
    , asPartialPattern
    , parse
    , unifyStringEq
      -- * keys
    , ltKey
    , plusKey
    , string2IntKey
    , int2StringKey
    , substrKey
    , lengthKey
    , findKey
    , string2BaseKey
    , chrKey
    , ordKey
    , token2StringKey
    , string2TokenKey
    ) where

import Prelude.Kore

import Control.Error
    ( MaybeT
    )
import qualified Control.Monad as Monad
import Data.Char
    ( chr
    , ord
    )
import qualified Data.HashMap.Strict as HashMap
import Data.List
    ( findIndex
    )
import Data.Map.Strict
    ( Map
    )
import qualified Data.Map.Strict as Map
import Data.Text
    ( Text
    )
import qualified Data.Text as Text
import qualified Data.Text.Read as Text
import Numeric
    ( readOct
    )
import qualified Text.Megaparsec as Parsec

import Kore.Attribute.Hook
    ( Hook (..)
    )
import qualified Kore.Builtin.Bool as Bool
import qualified Kore.Builtin.Builtin as Builtin
import Kore.Builtin.EqTerm
import qualified Kore.Builtin.Int as Int
import Kore.Builtin.String.String
import qualified Kore.Domain.Builtin as Domain
import qualified Kore.Error
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Symbol
    ( symbolHook
    )
import Kore.Internal.TermLike as TermLike
import Kore.Step.Simplification.NotSimplifier
    ( NotSimplifier (..)
    )
import Kore.Step.Simplification.Simplify
    ( BuiltinAndAxiomSimplifier
    , TermSimplifier
    )
import Kore.Unification.Unify as Unify

{- | Verify that the sort is hooked to the builtin @String@ sort.

  See also: 'sort', 'Builtin.verifySort'

 -}
assertSort :: Builtin.SortVerifier
assertSort = Builtin.verifySort sort

verifiers :: Builtin.Verifiers
verifiers =
    Builtin.Verifiers
        { sortDeclVerifiers
        , symbolVerifiers
        , patternVerifierHook
        }

{- | Verify that hooked sort declarations are well-formed.

  See also: 'Builtin.verifySortDecl'

 -}
sortDeclVerifiers :: Builtin.SortDeclVerifiers
sortDeclVerifiers = HashMap.fromList [ (sort, Builtin.verifySortDecl) ]

{- | Verify that hooked symbol declarations are well-formed.

  See also: 'Builtin.verifySymbol'

 -}
symbolVerifiers :: Builtin.SymbolVerifiers
symbolVerifiers =
    HashMap.fromList
    [   ( eqKey
        , Builtin.verifySymbol Bool.assertSort [assertSort, assertSort]
        )
    ,   ( ltKey
        , Builtin.verifySymbol Bool.assertSort [assertSort, assertSort]
        )
    ,   ( plusKey
        , Builtin.verifySymbol assertSort [assertSort, assertSort]
        )
    ,   ( substrKey
        , Builtin.verifySymbol
            assertSort
            [assertSort, Int.assertSort, Int.assertSort]
        )
    ,   ( lengthKey
        , Builtin.verifySymbol Int.assertSort [assertSort]
        )
    ,   ( findKey
        , Builtin.verifySymbol
            Int.assertSort
            [assertSort, assertSort, Int.assertSort]
        )
    ,   ( string2BaseKey
        , Builtin.verifySymbol
            Int.assertSort
            [assertSort, Int.assertSort]
        )
    ,   ( string2IntKey
        , Builtin.verifySymbol Int.assertSort [assertSort]
        )
    ,   ( int2StringKey
        , Builtin.verifySymbol assertSort [Int.assertSort]
        )
    ,   ( chrKey
        , Builtin.verifySymbol assertSort [Int.assertSort]
        )
    ,   ( ordKey
        , Builtin.verifySymbol Int.assertSort [assertSort]
        )
    ,   ( token2StringKey
        , Builtin.verifySymbol
            assertSort
            [Builtin.verifySortHasDomainValues]
        )
    ,   ( string2TokenKey
        , Builtin.verifySymbol
            Builtin.verifySortHasDomainValues
            [assertSort]
        )
    ]

{- | Verify that domain value patterns are well-formed.
 -}
patternVerifierHook :: Builtin.PatternVerifierHook
patternVerifierHook =
    Builtin.domainValuePatternVerifierHook sort patternVerifierWorker
  where
    patternVerifierWorker domainValue =
        case externalChild of
            StringLiteral_ internalStringValue ->
                (return . BuiltinF . Domain.BuiltinString)
                    Domain.InternalString
                        { internalStringSort
                        , internalStringValue
                        }
            _ -> Kore.Error.koreFail "Expected literal string"
      where
        DomainValue { domainValueSort = internalStringSort } = domainValue
        DomainValue { domainValueChild = externalChild } = domainValue

-- | get the value from a (possibly encoded) domain value
extractStringDomainValue
    :: Text -- ^ error message Context
    -> Builtin (TermLike variable)
    -> Text
extractStringDomainValue ctx =
    \case
        Domain.BuiltinString internal ->
            internalStringValue
          where
            Domain.InternalString { internalStringValue } = internal
        _ ->
            Builtin.verifierBug
            $ Text.unpack ctx ++ ": Domain value is not a string"

{- | Parse a string literal.
 -}
parse :: Builtin.Parser Text
parse = Text.pack <$> Parsec.many Parsec.anySingle

{- | Abort function evaluation if the argument is not a String domain value.

    If the operand pattern is not a domain value, the function is simply
    'NotApplicable'. If the operand is a domain value, but not represented
    by a 'BuiltinDomainMap', it is a bug.

 -}
expectBuiltinString
    :: Monad m
    => String  -- ^ Context for error message
    -> TermLike variable  -- ^ Operand pattern
    -> MaybeT m Text
expectBuiltinString ctx =
    \case
        Builtin_ domain ->
            case domain of
                Domain.BuiltinString internal ->
                    return internalStringValue
                  where
                    Domain.InternalString { internalStringValue } = internal
                _ ->
                    Builtin.verifierBug
                    $ ctx ++ ": Domain value is not a string"
        _ -> empty


evalSubstr :: BuiltinAndAxiomSimplifier
evalSubstr = Builtin.functionEvaluator evalSubstr0
  where
    substr :: Int -> Int -> Text -> Text
    substr startIndex endIndex =
        Text.take (endIndex - startIndex) . Text.drop startIndex

    evalSubstr0 resultSort [_str, _start, _end] = do
        _str   <- expectBuiltinString substrKey _str
        _start <- fromInteger <$> Int.expectBuiltinInt substrKey _start
        _end   <- fromInteger <$> Int.expectBuiltinInt substrKey _end
        substr _start _end _str
            & asPattern resultSort
            & return
    evalSubstr0 _ _ = Builtin.wrongArity substrKey

evalLength :: BuiltinAndAxiomSimplifier
evalLength = Builtin.functionEvaluator evalLength0
  where
    evalLength0 resultSort [_str] = do
        _str <- expectBuiltinString lengthKey _str
        Text.length _str
            & toInteger
            & Int.asPattern resultSort
            & return
    evalLength0 _ _ = Builtin.wrongArity lengthKey

evalFind :: BuiltinAndAxiomSimplifier
evalFind = Builtin.functionEvaluator evalFind0
  where
    maybeNotFound :: Maybe Int -> Integer
    maybeNotFound = maybe (-1) toInteger

    evalFind0 resultSort [_str, _substr, _idx] = do
        _str <- expectBuiltinString findKey _str
        _substr <- expectBuiltinString findKey _substr
        _idx <- fromInteger <$> Int.expectBuiltinInt substrKey _idx
        let result =
                findIndex
                    (Text.isPrefixOf _substr)
                    (Text.tails . Text.drop _idx $ _str)
        maybeNotFound result
            & Int.asPattern resultSort
            & return
    evalFind0 _ _ = Builtin.wrongArity findKey

evalString2Base :: BuiltinAndAxiomSimplifier
evalString2Base = Builtin.functionEvaluator evalString2Base0
  where
    evalString2Base0 resultSort [_str, _base] = do
        _str  <- expectBuiltinString string2BaseKey _str
        _base <- Int.expectBuiltinInt string2BaseKey _base
        let readN =
                case _base of
                    -- no builtin reader for number in octal notation
                    8  -> \s ->
                        case readOct $ Text.unpack s of
                            [(result, "")] -> Right (result, "")
                            _              -> Left ""
                    10 -> Text.signed Text.decimal
                    16 -> Text.hexadecimal
                    _  -> const empty
        case readN _str of
            Right (result, Text.unpack -> "") ->
                return (Int.asPattern resultSort result)
            _ -> return (Pattern.bottomOf resultSort)
    evalString2Base0 _ _ = Builtin.wrongArity string2BaseKey

evalString2Int :: BuiltinAndAxiomSimplifier
evalString2Int = Builtin.functionEvaluator evalString2Int0
  where
    evalString2Int0 resultSort [_str] = do
        _str <- expectBuiltinString string2IntKey _str
        case Text.signed Text.decimal _str of
            Right (result, Text.unpack -> "") ->
                return (Int.asPattern resultSort result)
            _ -> return (Pattern.bottomOf resultSort)
    evalString2Int0 _ _ = Builtin.wrongArity string2IntKey

evalInt2String :: BuiltinAndAxiomSimplifier
evalInt2String = Builtin.functionEvaluator evalInt2String0
  where
    evalInt2String0 resultSort [_int] = do
        _int <- Int.expectBuiltinInt int2StringKey _int
        Text.pack (show _int)
            & asPattern resultSort
            & return
    evalInt2String0 _ _ = Builtin.wrongArity int2StringKey

evalChr :: BuiltinAndAxiomSimplifier
evalChr = Builtin.functionEvaluator evalChr0
  where
    evalChr0 resultSort [_n] = do
        _n <- Int.expectBuiltinInt chrKey _n
        Text.singleton (chr $ fromIntegral _n)
            & asPattern resultSort
            & return
    evalChr0 _ _ = Builtin.wrongArity chrKey

evalOrd :: BuiltinAndAxiomSimplifier
evalOrd = Builtin.functionEvaluator evalOrd0
  where
    evalOrd0 resultSort [_str] = do
        _str <- expectBuiltinString ordKey _str
        let result
              | Text.length _str == 1 = charToOrdInt (Text.head _str)
              | otherwise = Pattern.bottomOf resultSort
        return result
      where
        charToOrdInt =
            Int.asPattern resultSort
            . toInteger
            . ord
    evalOrd0 _ _ = Builtin.wrongArity ordKey

evalToken2String :: BuiltinAndAxiomSimplifier
evalToken2String = Builtin.functionEvaluator evalToken2String0
  where
    evalToken2String0 resultSort [_dv] = do
        _dv <- Builtin.expectDomainValue token2StringKey _dv
        return (asPattern resultSort _dv)
    evalToken2String0 _ _ = Builtin.wrongArity token2StringKey

evalString2Token :: BuiltinAndAxiomSimplifier
evalString2Token = Builtin.functionEvaluator evalString2Token0
  where
    evalString2Token0 resultSort [_str] = do
        _str <- expectBuiltinString string2TokenKey _str
        Builtin.makeDomainValuePattern resultSort _str
            & return
    evalString2Token0 _ _ = Builtin.wrongArity token2StringKey

{- | Implement builtin function evaluation.
 -}
builtinFunctions :: Map Text BuiltinAndAxiomSimplifier
builtinFunctions =
    Map.fromList
    [ comparator eqKey (==)
    , comparator ltKey (<)
    , binaryOperator plusKey Text.append
    , (substrKey, evalSubstr)
    , (lengthKey, evalLength)
    , (findKey, evalFind)
    , (string2BaseKey, evalString2Base)
    , (string2IntKey, evalString2Int)
    , (int2StringKey, evalInt2String)
    , (chrKey, evalChr)
    , (ordKey, evalOrd)
    , (token2StringKey, evalToken2String)
    , (string2TokenKey, evalString2Token)
    ]
  where
    comparator name op =
        ( name, Builtin.binaryOperator extractStringDomainValue
            Bool.asPattern name op )
    binaryOperator name op =
        ( name, Builtin.binaryOperator extractStringDomainValue
            asPattern name op )

{- | Match the @STRING.eq@ hooked symbol.
-}
matchStringEqual :: TermLike variable -> Maybe (EqTerm (TermLike variable))
matchStringEqual =
    matchEqTerm $ \symbol ->
        do
            hook2 <- (getHook . symbolHook) symbol
            Monad.guard (hook2 == eqKey)
        & isJust

{- | Unification of the @STRING.eq@ symbol

This function is suitable only for equality simplification.

-}
unifyStringEq
    :: forall variable unifier
    .  InternalVariable variable
    => MonadUnify unifier
    => TermSimplifier variable unifier
    -> NotSimplifier unifier
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
unifyStringEq unifyChildren notSimplifier a b =
    worker a b <|> worker b a
  where
    worker termLike1 termLike2
      | Just eqTerm <- matchStringEqual termLike1
      , isFunctionPattern termLike1
      = unifyEqTerm unifyChildren notSimplifier eqTerm termLike2
      | otherwise = empty
