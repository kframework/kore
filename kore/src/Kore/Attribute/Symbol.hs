{-# LANGUAGE TemplateHaskell #-}

{- |
Description : Symbol declaration attributes
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

This module is intended to be imported qualified:
@
import qualified Kore.Attribute.Symbol as Attribute
@

 -}

module Kore.Attribute.Symbol
    ( Symbol (..)
    , StepperAttributes
    , defaultSymbolAttributes
    -- * Function symbols
    , lensFunction, Function (..)
    , functionAttribute
    , isFunction_, isFunction
    -- * Functional symbols
    , lensFunctional, Functional (..)
    , functionalAttribute
    , isFunctional_, isFunctional
    -- * Constructor symbols
    , lensConstructor, Constructor (..)
    , constructorAttribute
    , isConstructor_
    -- * Injective symbols
    , lensInjective, Injective (..)
    , injectiveAttribute
    , isInjective_, isInjective
    -- * Non-simplifiable symbols
    , isNonSimplifiable_, isNonSimplifiable
    -- * Sort injection symbols
    , lensSortInjection, SortInjection (..)
    , sortInjectionAttribute
    , isSortInjection_
    -- * Hooked symbols
    , lensHook, Hook (..)
    , hookAttribute
    -- * SMT symbols
    , Smthook (..)
    , smthookAttribute
    , Smtlib (..)
    , smtlibAttribute
    -- * Total symbols
    , isTotal_, isTotal
    ) where

import           Control.DeepSeq
                 ( NFData )
import qualified Control.Lens as Lens hiding
                 ( makeLenses )
import qualified Control.Lens.TH.Rules as Lens
import           Control.Monad
                 ( (>=>) )
import           Data.Default
import           Data.Reflection
                 ( Given, given )
import           GHC.Generics
                 ( Generic )

import Kore.AST.Common
       ( SymbolOrAlias )
import Kore.Attribute.Constructor
import Kore.Attribute.Function
import Kore.Attribute.Functional
import Kore.Attribute.Hook
import Kore.Attribute.Injective
import Kore.Attribute.Parser
       ( ParseAttributes (..) )
import Kore.Attribute.Smthook
import Kore.Attribute.Smtlib
import Kore.Attribute.SortInjection
import Kore.IndexedModule.MetadataTools
       ( MetadataTools (..) )

{- | Symbol attributes used during Kore execution.

@Symbol@ records the declared attributes of a Kore symbol, but the effective
attributes can be different; for example, constructors and sort injections are
injective, even if their declaration is not given the @injective@ attribute. To
view the effective attributes, use the functions defined in this module.

 -}
data Symbol =
    Symbol
    { function      :: !Function
      -- ^ Whether a symbol represents a function
    , functional    :: !Functional
      -- ^ Whether a symbol is functional
    , constructor   :: !Constructor
      -- ^ Whether a symbol represents a constructor
    , injective     :: !Injective
      -- ^ Whether a symbol represents an injective function
    , sortInjection :: !SortInjection
      -- ^ Whether a symbol is a sort injection
    , hook          :: !Hook
      -- ^ The builtin sort or symbol hooked to a sort or symbol
    , smtlib        :: !Smtlib
    , smthook       :: !Smthook
    }
    deriving (Eq, Ord, Generic, Show)

type StepperAttributes = Symbol

Lens.makeLenses ''Symbol

instance NFData Symbol

instance ParseAttributes Symbol where
    parseAttribute attr =
        lensFunction (parseAttribute attr)
        >=> lensFunctional (parseAttribute attr)
        >=> lensConstructor (parseAttribute attr)
        >=> lensSortInjection (parseAttribute attr)
        >=> lensInjective (parseAttribute attr)
        >=> lensHook (parseAttribute attr)
        >=> lensSmtlib (parseAttribute attr)
        >=> lensSmthook (parseAttribute attr)

defaultSymbolAttributes :: Symbol
defaultSymbolAttributes =
    Symbol
        { function       = def
        , functional     = def
        , constructor    = def
        , injective      = def
        , sortInjection  = def
        , hook           = def
        , smtlib         = def
        , smthook        = def
        }

-- | See also: 'defaultSymbolAttributes'
instance Default Symbol where
    def = defaultSymbolAttributes

-- | Is a symbol total (non-@\\bottom@)?
isTotal_
    :: Given (MetadataTools level StepperAttributes)
    => SymbolOrAlias level
    -> Bool
isTotal_ = isTotal . symAttributes given

-- | Is a symbol total (non-@\\bottom@)?
isTotal :: StepperAttributes -> Bool
isTotal = do
    isFunctional' <- isFunctional
    Constructor isConstructor' <- Lens.view lensConstructor
    return (isFunctional' || isConstructor')

{- | Is the symbol a function?

A symbol is a function if it is given the @function@ attribute or if it is
functional.

See also: 'functionAttribute', 'isFunctional'

 -}
isFunction_
    :: Given (MetadataTools level StepperAttributes)
    => SymbolOrAlias level
    -> Bool
isFunction_ = isFunction . symAttributes given

{- | Is the symbol a function?

A symbol is a function if it is given the @function@ attribute or if it is
functional.

See also: 'functionAttribute', 'isFunctional'

 -}
isFunction :: StepperAttributes -> Bool
isFunction = do
    Function isFunction' <- Lens.view lensFunction
    isFunctional' <- isFunctional
    return (isFunction' || isFunctional')

{- | Is the symbol functional?

A symbol is functional if it is given the @functional@ attribute or the
@sortInjection@ attribute.

See also: 'isFunctional', 'functionalAttribute', 'sortInjectionAttribute'

 -}
isFunctional_
    :: Given (MetadataTools level StepperAttributes)
    => SymbolOrAlias level
    -> Bool
isFunctional_ = isFunctional . symAttributes given

{- | Is the symbol functional?

A symbol is functional if it is given the @functional@ attribute or the
@sortInjection@ attribute.

See also: 'functionalAttribute', 'sortInjectionAttribute'

 -}
isFunctional :: StepperAttributes -> Bool
isFunctional = do
    Functional isFunctional' <- functional
    SortInjection isSortInjection' <- sortInjection
    return (isFunctional' || isSortInjection')

-- | Is the symbol a constructor?
isConstructor_
    :: Given (MetadataTools level StepperAttributes)
    => SymbolOrAlias level
    -> Bool
isConstructor_ = isConstructor . constructor . symAttributes given

{- | Is the symbol injective?

A symbol is injective if it is given the @injective@ attribute, the
@constructor@ attribute, or the @sortInjection@ attribute.

See also: 'isInjective', 'injectiveAttribute', 'constructorAttribute',
'sortInjectionAttribute'
 -}
isInjective_
    :: Given (MetadataTools level StepperAttributes)
    => SymbolOrAlias level
    -> Bool
isInjective_ = isInjective . symAttributes given

{- | Is the symbol injective?

A symbol is injective if it is given the @injective@ attribute, the
@constructor@ attribute, or the @sortInjection@ attribute.

See also: 'injectiveAttribute', 'constructorAttribute', 'sortInjectionAttribute'

 -}
isInjective :: StepperAttributes -> Bool
isInjective = do
    Injective isInjective' <- injective
    Constructor isConstructor' <- constructor
    SortInjection isSortInjection' <- sortInjection
    return (isInjective' || isConstructor' || isSortInjection')

{- | Is the symbol a sort injection?

See also: 'isSortInjection'

 -}
isSortInjection_
    :: (Given (MetadataTools level StepperAttributes))
    => SymbolOrAlias level
    -> Bool
isSortInjection_ =
    isSortInjection . sortInjection . symAttributes given

-- | Is a symbol not simplifiable?
--
-- sigma is non-simplifiable if whenever we have the following
-- * Context[y] is not simplifiable to a pattern without y
-- * sigma(..., x, ...) != bottom
-- then Context[sigma(..., x, ...)] cannot be simplified to either x or
-- something that does not contain x as a free variable.
--
-- Note that constructors and sort injection are natural candidates for
-- non-simplifiable patterns. Builtins like 'element' (for sets, lists and maps)
-- are also good candidates for non-simplifiable symbols.
--
-- Builtins like 'concat' need an additional condition, i.e. that the arguments
-- are not .Map.
isNonSimplifiable_
    :: Given (MetadataTools level StepperAttributes)
    => SymbolOrAlias level
    -> Bool
isNonSimplifiable_ = isNonSimplifiable . symAttributes given

-- | Is a symbol non-simplifiable?
isNonSimplifiable :: StepperAttributes -> Bool
isNonSimplifiable = do
    -- TODO(virgil): Add a 'non-simplifiable' attribute so that we can include
    -- more symbols here (e.g. Map.concat)
    Constructor isConstructor' <- constructor
    SortInjection isSortInjection' <- sortInjection
    return (isSortInjection' || isConstructor')
