{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Syntax.PatternF
    ( PatternF (..)
    , mapVariables
    , traverseVariables
    -- * Pure pattern heads
    , groundHead
    , constant
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import qualified Data.Deriving as Deriving
import           Data.Functor.Classes
import           Data.Functor.Identity
                 ( Identity (..) )
import           Data.Hashable
import           Data.Text
                 ( Text )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Debug
import Kore.Sort
import Kore.Syntax.And
import Kore.Syntax.Application
import Kore.Syntax.Bottom
import Kore.Syntax.Ceil
import Kore.Syntax.CharLiteral
import Kore.Syntax.DomainValue
import Kore.Syntax.Equals
import Kore.Syntax.Exists
import Kore.Syntax.Floor
import Kore.Syntax.Forall
import Kore.Syntax.Iff
import Kore.Syntax.Implies
import Kore.Syntax.In
import Kore.Syntax.Next
import Kore.Syntax.Not
import Kore.Syntax.Or
import Kore.Syntax.Rewrites
import Kore.Syntax.SetVariable
import Kore.Syntax.StringLiteral
import Kore.Syntax.Top
import Kore.Syntax.Variable
import Kore.Unparser

{- | 'PatternF' is the 'Base' functor of Kore patterns

-}
data PatternF variable child
    = AndF           !(And Sort child)
    | ApplicationF   !(Application SymbolOrAlias child)
    | BottomF        !(Bottom Sort child)
    | CeilF          !(Ceil Sort child)
    | DomainValueF   !(DomainValue Sort child)
    | EqualsF        !(Equals Sort child)
    | ExistsF        !(Exists Sort variable child)
    | FloorF         !(Floor Sort child)
    | ForallF        !(Forall Sort variable child)
    | IffF           !(Iff Sort child)
    | ImpliesF       !(Implies Sort child)
    | InF            !(In Sort child)
    | NextF          !(Next Sort child)
    | NotF           !(Not Sort child)
    | OrF            !(Or Sort child)
    | RewritesF      !(Rewrites Sort child)
    | StringLiteralF !StringLiteral
    | CharLiteralF   !CharLiteral
    | TopF           !(Top Sort child)
    | VariableF      !variable
    | InhabitantF    !Sort
    | SetVariableF   !(SetVariable variable)
    deriving (Foldable, Functor, GHC.Generic, Traversable)

Deriving.deriveEq1 ''PatternF
Deriving.deriveOrd1 ''PatternF
Deriving.deriveShow1 ''PatternF

instance (Eq variable, Eq child) => Eq (PatternF variable child) where
    (==) = eq1
    {-# INLINE (==) #-}

instance (Ord variable, Ord child) => Ord (PatternF variable child) where
    compare = compare1
    {-# INLINE compare #-}

instance (Show variable, Show child) => Show (PatternF variable child) where
    showsPrec = showsPrec1
    {-# INLINE showsPrec #-}

instance SOP.Generic (PatternF variable child)

instance SOP.HasDatatypeInfo (PatternF variable child)

instance (Debug variable, Debug child) => Debug (PatternF variable child)

instance
    (Hashable child, Hashable variable) =>
    Hashable (PatternF variable child)

instance (NFData child, NFData variable) => NFData (PatternF variable child)

instance
    (SortedVariable variable, Unparse variable, Unparse child) =>
    Unparse (PatternF variable child)
  where
    unparse = unparseGeneric
    unparse2 = unparse2Generic

{- | Use the provided mapping to replace all variables in a 'PatternF' head.

__Warning__: @mapVariables@ will capture variables if the provided mapping is
not injective!

-}
mapVariables
    :: (variable1 -> variable2)
    -> PatternF variable1 child
    -> PatternF variable2 child
mapVariables mapping =
    runIdentity . traverseVariables (Identity . mapping)
{-# INLINE mapVariables #-}

{- | Use the provided traversal to replace all variables in a 'PatternF' head.

__Warning__: @traverseVariables@ will capture variables if the provided
traversal is not injective!

-}
traverseVariables
    :: Applicative f
    => (variable1 -> f variable2)
    -> PatternF variable1 child
    -> f (PatternF variable2 child)
traverseVariables traversing =
    \case
        -- Non-trivial cases
        ExistsF any0 -> ExistsF <$> traverseVariablesExists any0
        ForallF all0 -> ForallF <$> traverseVariablesForall all0
        VariableF variable -> VariableF <$> traversing variable
        SetVariableF (SetVariable variable) ->
            SetVariableF . SetVariable <$> traversing variable
        -- Trivial cases
        AndF andP -> pure (AndF andP)
        ApplicationF appP -> pure (ApplicationF appP)
        BottomF botP -> pure (BottomF botP)
        CeilF ceilP -> pure (CeilF ceilP)
        DomainValueF dvP -> pure (DomainValueF dvP)
        EqualsF eqP -> pure (EqualsF eqP)
        FloorF flrP -> pure (FloorF flrP)
        IffF iffP -> pure (IffF iffP)
        ImpliesF impP -> pure (ImpliesF impP)
        InF inP -> pure (InF inP)
        NextF nxtP -> pure (NextF nxtP)
        NotF notP -> pure (NotF notP)
        OrF orP -> pure (OrF orP)
        RewritesF rewP -> pure (RewritesF rewP)
        StringLiteralF strP -> pure (StringLiteralF strP)
        CharLiteralF charP -> pure (CharLiteralF charP)
        TopF topP -> pure (TopF topP)
        InhabitantF s -> pure (InhabitantF s)
  where
    traverseVariablesExists Exists { existsSort, existsVariable, existsChild } =
        Exists existsSort <$> traversing existsVariable <*> pure existsChild
    traverseVariablesForall Forall { forallSort, forallVariable, forallChild } =
        Forall forallSort <$> traversing forallVariable <*> pure forallChild

-- | Given an 'Id', 'groundHead' produces the head of an 'Application'
-- corresponding to that argument.
groundHead :: Text -> AstLocation -> SymbolOrAlias
groundHead ctor location = SymbolOrAlias
    { symbolOrAliasConstructor = Id
        { getId = ctor
        , idLocation = location
        }
    , symbolOrAliasParams = []
    }

-- | Given a head and a list of children, produces an 'ApplicationF'
--  applying the given head to the children
apply :: SymbolOrAlias -> [child] -> PatternF variable child
apply patternHead patterns = ApplicationF Application
    { applicationSymbolOrAlias = patternHead
    , applicationChildren = patterns
    }

-- |Applies the given head to the empty list of children to obtain a
-- constant 'ApplicationF'
constant :: SymbolOrAlias -> PatternF variable child
constant patternHead = apply patternHead []
