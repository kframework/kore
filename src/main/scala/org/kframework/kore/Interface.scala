package org.kframework.kore

trait Definition {
  def att: Attributes

  def modules: Seq[Module]
}

object Definition {
  def unapply(arg: Definition): Option[(Seq[Module], Attributes)] = Some(arg.modules, arg.att)
}

trait Module {
  def name: ModuleName

  def decls: Seq[Declaration]

  def att: Attributes
}

object Module {
  def unapply(arg: Module): Option[(ModuleName, Seq[Declaration], Attributes)] = Some(arg.name, arg.decls, arg.att)
}

trait Declaration

/*
trait Import extends Sentence {
  def name: ModuleName

  def att: Attributes
}

object Import {
  def unapply(arg: Import): Option[(ModuleName, Attributes)] = Some(arg.name, arg.att)
}
*/

trait SortDeclaration extends Declaration {
  def params: Seq[SortVariable]

  def sort: Sort

  def att: Attributes
}

object SortDeclaration {
  def unapply(arg: SortDeclaration): Option[(Seq[SortVariable], Sort, Attributes)]
  = Some(arg.params, arg.sort, arg.att)
}

trait SymbolDeclaration extends Declaration {
  def symbol: Symbol

  def argSorts: Seq[Sort]

  def returnSort: Sort

  def att: Attributes
}

object AliasDeclaration {
  def unapply(arg: AliasDeclaration): Option[(Alias, Seq[Sort], Sort, Attributes)]
  = Some(arg.alias, arg.argSorts, arg.returnSort, arg.att)
}
trait AliasDeclaration extends Declaration {
  def alias: Alias

  def argSorts: Seq[Sort]

  def returnSort: Sort

  def att: Attributes
}

object SymbolDeclaration {
  def unapply(arg: SymbolDeclaration): Option[(Symbol, Seq[Sort], Sort, Attributes)]
  = Some(arg.symbol, arg.argSorts, arg.returnSort, arg.att)
}

trait AxiomDeclaration extends Declaration {
  def params: Seq[SortVariable]

  def pattern: Pattern

  def att: Attributes
}

object AxiomDeclaration {
  def unapply(arg: AxiomDeclaration): Option[(Seq[SortVariable], Pattern, Attributes)]
  = Some(arg.params, arg.pattern, arg.att)
}

trait Attributes {
  def patterns: Seq[Pattern]
}

object Attributes {
  def unapply(arg: Attributes): Option[Seq[Pattern]] = Some(arg.patterns)
}

trait Pattern

trait Variable extends Pattern {
  def name: String

  def sort: Sort
}

object Variable {
  def unapply(arg: Variable): Option[(String, Sort)] = Some(arg.name, arg.sort)
}

trait Application extends Pattern {
  def head: SymbolOrAlias

  def args: Seq[Pattern]
}

object Application {
  def unapply(arg: Application): Option[(SymbolOrAlias, Seq[Pattern])] = Some(arg.head, arg.args)
}

trait Top extends Pattern {
  def s: Sort
}

object Top {
  def unapply(arg: Top): Option[Sort] = Some(arg.s)
}

trait Bottom extends Pattern {
  def s: Sort
}

object Bottom {
  def unapply(arg: Bottom): Option[Sort] = Some(arg.s)
}

trait And extends Pattern {
  def s: Sort

  def _1: Pattern

  def _2: Pattern
}

object And {
  def unapply(arg: And): Option[(Sort, Pattern, Pattern)] = Some(arg.s, arg._1, arg._2)
}

trait Or extends Pattern {
  def s: Sort

  def _1: Pattern

  def _2: Pattern
}

object Or {
  def unapply(arg: Or): Option[(Sort, Pattern, Pattern)] = Some(arg.s, arg._1, arg._2)
}

trait Not extends Pattern {
  def s: Sort

  def _1: Pattern
}

object Not {
  def unapply(arg: Not): Option[(Sort, Pattern)] = Some(arg.s, arg._1)
}

trait Implies extends Pattern {
  def s: Sort

  def _1: Pattern

  def _2: Pattern
}

object Implies {
  def unapply(arg: Implies): Option[(Sort, Pattern, Pattern)] = Some(arg.s, arg._1, arg._2)
}

trait Iff extends Pattern {
  def s: Sort

  def _1: Pattern

  def _2: Pattern
}

object Iff {
  def unapply(arg: Iff): Option[(Sort, Pattern, Pattern)] = Some(arg.s, arg._1, arg._2)
}

trait Exists extends Pattern {
  def s: Sort // this is the sort of the whole exists pattern, not the sort of the binding variable v

  def v: Variable

  def p: Pattern
}

object Exists {
  def unapply(arg: Exists): Option[(Sort, Variable, Pattern)] = Some(arg.s, arg.v, arg.p)
}

trait Forall extends Pattern {
  def s: Sort

  def v: Variable

  def p: Pattern
}

object Forall {
  def unapply(arg: Forall): Option[(Sort, Variable, Pattern)] = Some(arg.s, arg.v, arg.p)
}

trait Next extends Pattern {
  def s: Sort

  def _1: Pattern
}

object Next {
  def unapply(arg: Next): Option[(Sort, Pattern)] = Some(arg.s, arg._1)
}

/**
  * \rewrites(P, Q) is defined as a predicate pattern floor(P implies Q)
  * Therefore a rewrites-to pattern is parametric on two sorts.
  * One is the sort of patterns P and Q;
  * The other is the sort of the context.
  */
trait Rewrites extends Pattern {
  def s: Sort // the sort of the two patterns P and Q

  def rs: Sort // the sort of the context where the rewrites-to pattern is being placed.

  def _1: Pattern

  def _2: Pattern
}

object Rewrites {
  def unapply(arg: Rewrites): Option[(Sort, Sort, Pattern, Pattern)] =
    Some(arg.s, arg.rs, arg._1, arg._2)
}

trait Equals extends Pattern {
  def s: Sort // the sort of the two patterns that are being compared

  def rs: Sort // the sort of the context where the equality pattern is being placed

  def _1: Pattern

  def _2: Pattern
}

object Equals {
  def unapply(arg: Equals): Option[(Sort, Sort, Pattern, Pattern)]
  = Some(arg.s, arg.rs, arg._1, arg._2)
}

/**
  * \mem(X, P) is a predicate pattern that checks whether a variable x
  * is a member of the pattern P.
  * It is mathematically defined as ceil(X and P)
  */
trait Mem extends Pattern {
  def s: Sort // the sort of X and P

  def rs: Sort // the context sort

  def x: Variable

  def p: Pattern
}

object Mem {
  def unapply(arg: Mem): Option[(Sort, Sort, Variable, Pattern)] =
    Some(arg.s, arg.rs, arg.x, arg.p)
}

/**
  * \subset(P,Q) is a predicate pattern that checks whether P is a subset of Q.
  */
trait Subset extends Pattern {
  def s: Sort // the sort of P and Q

  def rs: Sort // the context sort

  def _1: Pattern

  def _2: Pattern
}

object Subset {
  def unapply(arg: Subset): Option[(Sort, Sort, Pattern, Pattern)] =
    Some(arg.s, arg.rs, arg._1, arg._2)
}

// String literals <string> are considered as meta-level patterns of sort #String
trait StringLiteral extends Pattern {
  def str: String
}

object StringLiteral {
  def unapply(arg: StringLiteral): Option[String] = Some(arg.str)
}

trait ModuleName {
  def str: String
}

object ModuleName {
  def unapply(arg: ModuleName): Option[String] = Some(arg.str)
}

/** A sort can be either a sort variable or of the form C{s1,...,sn}
  * where C is called the sort constructor and s1,...,sn are sort parameters.
  * We call sorts that are of the form C{s1,...,sn} compound sorts because
  * I don't know a better name.
  */

trait Sort

trait SortVariable extends Sort {
  def name: String
}

object SortVariable {
  def unapply(arg: SortVariable): Option[String] = Some(arg.name)
}

/** A compound sort is of the form C{s1,...,sn}
  * For example:
  * Nat{} List{Nat{}} List{S} Map{S,List{S}} Map{Map{Nat{},Nat{}},Nat{}}
  */
trait CompoundSort extends Sort {
  def ctr: String        // sort constructor
  def params: Seq[Sort]  // sort parameters
}

object CompoundSort {
  def unapply(arg: CompoundSort): Option[(String, Seq[Sort])] = Some(arg.ctr, arg.params)
}

/** A symbol-or-alias is of the form C{s1,...,sn}
  * where C is called a constructor and s1,...,sn are sort parameters.
  * In the Semantics of K document, SymbolOrAlias is called the nonterminal <head>
  */
trait SymbolOrAlias {
  def ctr: String

  def params: Seq[Sort]
}

object SymbolOrAlias {
  def unapply(arg: SymbolOrAlias): Option[(String, Seq[Sort])] =
    Some(arg.ctr, arg.params)
}

trait Symbol extends SymbolOrAlias

trait Alias extends SymbolOrAlias

trait Builders {

  def Definition(att: Attributes, modules: Seq[Module]): Definition

  def Module(name: ModuleName, decls: Seq[Declaration], att: Attributes): Module

  // def Import(name: ModuleName, att: Attributes): Sentence

  def SortDeclaration(params: Seq[SortVariable],
                      sort: Sort,
                      att: Attributes): Declaration

  def SymbolDeclaration(symbol: Symbol,
                        argSorts: Seq[Sort],
                        returnSort: Sort,
                        att: Attributes): Declaration

  def AliasDeclaration(alias: Alias,
                       argSorts: Seq[Sort],
                       returnSort: Sort,
                       att: Attributes): Declaration

  def AxiomDeclaration(params: Seq[SortVariable],
                       pattern: Pattern,
                       att: Attributes): Declaration

  def Attributes(att: Seq[Pattern]): Attributes

  def Variable(name: String, sort: Sort): Variable

  def Application(head: SymbolOrAlias, args: Seq[Pattern]): Pattern

  def Top(s: Sort): Pattern

  def Bottom(s: Sort): Pattern

  def And(s: Sort, _1: Pattern, _2: Pattern): Pattern

  def Or(s: Sort, _1: Pattern, _2: Pattern): Pattern

  def Not(s: Sort, _1: Pattern): Pattern

  def Implies(s: Sort, _1: Pattern, _2: Pattern): Pattern

  def Iff(s: Sort, _1: Pattern, _2: Pattern): Pattern

  def Exists(s:Sort, v: Variable, p: Pattern): Pattern

  def Forall(s: Sort, v: Variable, p: Pattern): Pattern

  def Next(s: Sort, _1: Pattern): Pattern

  def Rewrites(s: Sort, rs: Sort, _1: Pattern, _2: Pattern): Pattern

  def Equals(s: Sort, rs:Sort, _1: Pattern, _2: Pattern): Pattern

  def Mem(s: Sort, rs:Sort, x: Variable, p: Pattern): Pattern

  def Subset(s: Sort, rs:Sort, _1: Pattern, _2: Pattern): Pattern

  def StringLiteral(str: String): Pattern

  def ModuleName(str: String): ModuleName

  def SortVariable(name: String): SortVariable

  def CompoundSort(ctr: String, params: Seq[Sort]): CompoundSort

  def SymbolOrAlias(ctr: String, params: Seq[Sort]): SymbolOrAlias

  def Symbol(str: String, params: Seq[Sort]): Symbol

  def Alias(str: String, params: Seq[Sort]): Alias

}
