;
; utilities.scm
; Helper functions for OpenPsi
;
; Copyright (C) 2015-2016 OpenCog Foundation

(use-modules (ice-9 regex)) ; For string-match
(use-modules (srfi srfi-1)) ; For fold, delete-duplicates

(use-modules (opencog) (opencog exec))

; --------------------------------------------------------------
(define-public psi-prefix-str "OpenPsi: ")

; --------------------------------------------------------------
(define-public (psi-suffix-str a-string)
"
  psi-suffix-str STRING

  Given the string STRING, this removes the psi prefix string.
"
    (let ((z-match (string-match psi-prefix-str a-string)))
        (if z-match
            (match:suffix z-match)
            (error (string-append "The string argument must have the prefix: "
                "\"" psi-prefix-str "\". " "Instead got:" a-string) )
        )
    )
)

; --------------------------------------------------------------
(define-public (satisfaction-level rule)
"
  satisfaction-level RULE

  Given the RULE, return the probability that the RULE can be satisfied.
  XXX Except this doesn't return a probability, it just returns TRUE_TV
  or FALSE_TV. What is this supposed to really do???
"
; NOTE
; 1. See https://github.com/opencog/atomspace/issues/823 for why
;   psi-satisfiable? is used
; 2. Should a context evaluator be added here?????
; 3. What is the "right" way of communicating the level of information.
    (satisfiable? rule)
)

; --------------------------------------------------------------
(define-public (most-weighted-atoms atom-list)
"
  most-weighted-atoms ATOM-LIST

  Return a list of atoms with the highest weight. Any duplicate atoms
  in the list are removed.
  The weight of an atom is the product of the stength and confidence
  of the atom.

  XXX FIXME: I think this is trying to sort the list of atoms by weight.
  However, the algorithm is a bit opaque, and seems to be inefficient.
  Surely, there is a better way.

  XXX FIXME: if teh goal is a siderted list, then a better name is
  possible: e.g. sort-by-weight, or something like that.
"
    (define (weight x)
        (let ((rule-stv (cog-tv x))
              (context-stv (satisfaction-level x)))
            (* (tv-conf rule-stv) (tv-mean rule-stv)
               (tv-conf context-stv) (tv-conf context-stv))))

    (define (pick atom lst) ; prev is a `lst` and next `atom`
        (cond
            ; If the weight of the atom is less than the weight of the
            ; head of the list, then return the list.
            ; If the weight of the atom is greater than the weight of
            ; the head of the list, then return the atom.
            ; If the two weights are equal, place the atom at the end
            ; of the list, and return the list.
            ((> (weight (car lst)) (weight atom)) lst)
            ((= (weight (car lst)) (weight atom)) (append lst (list atom)))
            (else (list atom))))

    (if (null? atom-list)
        '()
       (delete-duplicates (fold pick (list (car atom-list)) atom-list))
    )
)

; --------------------------------------------------------------
(define-public (most-important-weighted-atoms atom-list)
"
  most-important-weighted-atoms ATOMs-LIST

  Return a list atoms sorted according to attention-value times
  truth-value weight.
"
    (define (weight x)
        (let ((a-stv (cog-tv x))
              (sti (assoc-ref (cog-av->alist (cog-av x)) 'sti)))
            (* (tv-conf a-stv) (tv-mean a-stv) sti)))

    (define (pick atom lst) ; prev is a `lst` and next `atom`
        (cond
            ((> (weight (car lst)) (weight atom)) lst)
            ((= (weight (car lst)) (weight atom)) (append lst (list atom)))
            (else (list atom))))

    (if (null? atom-list)
        '()
        (delete-duplicates (fold pick (list (car atom-list)) atom-list))
    )
)

; --------------------------------------------------------------

; Define a local (internal-use-only, thus not define-public) variant
; of the psi-rule? predicate, because the main one is too slow.  This
; checks to see if MEMB is ...
; -- a MemberLink
; -- has arity 2
; -- first elt is an ImplicationLink
; -- Second elt is a node starting with string "OpenPsi: "
;
; Internal-use only, thus, not define-public.
(define (psi-member? MEMB)
    (and
        (equal? 'MemberLink (cog-type MEMB))
        (equal? 2 (cog-arity MEMB))
        (let ((mem (cog-outgoing-set MEMB)))
            (and
                (equal? 'ImplicationLink (cog-type (car mem)))
                (cog-node-type? (cog-type (cadr mem)))
                (string-prefix? psi-prefix-str (cog-name (cadr mem)))
        ))
    ))

; --------------------------------------------------------------

(define-public (psi-get-exact-match ATOM)
"
  psi-get-exact-match ATOM - Return list of all of the MemberLinks
  holding rules whose context or action apply exactly (without
  any variables) to the ATOM. In other words, the ATOM appears
  directly in the context of the rule.

  All psi rules are members of some ruleset; this searches for and
  finds such MemberLinks.
"
    ;; Get all exact matches
    (define inset (cog-get-trunk ATOM))

    ;; Keep only those links that are of type MemberLink...
    ;; and, more precisely, a MmeberLink that is of a valid
    ;; psi-fule form.
    (filter psi-member?
        (delete-duplicates (cog-filter 'MemberLink inset)))
)

(define-public (psi-get-dual-match ATOM)
"
  psi-get-dual-match ATOM - Return list of the MemberLinks
  holding rules whose context or action might apply to ATOM,
  as a generalized case (i.e. containining variables).

  All psi rules are members of some ruleset; this searches for and
  finds such MemberLinks.
"
    (define set-of-duals (cog-execute! (DualLink ATOM)))

    ;; Get all patterned rules
    (define duset
        (concatenate
            (map cog-get-trunk (cog-outgoing-set set-of-duals))))

    ; Avoid garbaging up the atomspace.
    (cog-delete set-of-duals)

    ;; Keep only those links that are of type MemberLink...
    ;; and, more precisely, a MmeberLink that is of a valid
    ;; psi-fule form.
    (filter psi-member?
        (delete-duplicates (cog-filter 'MemberLink duset)))
)

(define-public (psi-get-members ATOM)
"
  psi-get-members ATOM - Return list of all of the MemberLinks
  holding rules whose context or action might apply to ATOM.

  All psi rules are members of some ruleset; this searches for and
  finds such MemberLinks.
"
    (delete-duplicates (concatenate! (list
        (psi-get-exact-match ATOM)
        (psi-get-dual-match ATOM)
    )))
)

; --------------------------------------------------------------
(define
    (psi-set-functionality functionlity is-eval tag-node functionality-name)
"
  psi-set-functionality FUNC IS-EVAL TAG FUNC-NAME

  Associate a function with a particular demand or modulator.

  FUNC is an atom that can be executed or evaluated. It will perform
    the functionality for the particular demand/modulator.

  Set IS-EVAL to #t if the functionality is evaluatable and #f if
    it is executable.

  TAG should be a demand or modulator node that the functionality will
    be assocaited with.

  FUNC-NAME is the type of functionality.
"
    ;; XXX FIXME -- there is no need to force the use of DPN's or DSN's
    ;; here. Any excutable or evaluatable atom should be allowed.
    (define (check-alias a-name)
        (if is-eval
            (cog-node 'DefinedPredicateNode a-name)
            (cog-node 'DefinedSchemaNode a-name)))

    (let* ( (name (string-append
                        psi-prefix-str functionality-name "-"
                        (cog-name tag-node)))
            (alias (check-alias name)))

        (if (null? alias)
            (begin
                (set! alias
                     (if is-eval
                         (DefinedPredicateNode name)
                         (DefinedSchemaNode name)))

                ;; XXX FIXME why do we need a DefineLink here???
                ;; why is an alias needed? what is the point of this?
                (DefineLink alias functionlity)
                (StateLink
                    (ListLink
                        (Node (string-append psi-prefix-str functionality-name))
                         tag-node)
                     alias)
                alias
            )
        )
        alias
    )
)

; --------------------------------------------------------------
(define (psi-get-functionality tag-node functionality-name)
"
  psi-get-functionality TAG FUNC-NAME

  Return a list with the node that represents the functionality for the given
  demand/modulator or nil if it doesn't exist.

  TAG should be a demand/modulator node that the functionality is
  being added to.

  FUNC-NAME should be the type of functionality.
"
    (define state
       (ListLink
           (Node (string-append psi-prefix-str functionality-name))
           tag-node))

    (cog-outgoing-set (cog-execute!
        (GetLink (StateLink state (Variable "$x")))))
)

; --------------------------------------------------------------
; --------------------------------------------------------------
; Getters and setters for openpsi-related entity/parameter values
;
; Presently the implementation assumes the values of openpsi parameters are
; normalized in [0 1]. The current values of the params are assumed to be stored
; in a StateLink or if not in a StateLink an attempt is made to evaluate or
; execute the atom to obtain a value.

(define (cog-get-state-value entity)
	(define query
		(Get
			(State
				entity
				(Variable "$n"))))
	(define result (cog-execute! query))
	;(cog-delete query) ; maybe more optimal to keep this in the atomspace
	(if (not (null? (cog-outgoing-set result)))
		(gar result)
		#f))


(define (cog-set-state-value entity value)
			(State
				entity
				value))


(define (psi-get-value entity)
"
  Get the current value of a psi-related entity. For entities with numerical
  values, and NumberNode is returned.
"
	;(define result #f)

	; Todo: Could potential optimize? here by using
	; psi-value-representation-type fucntion

	; First check for StateLink value
	(define result (cog-get-state-value entity))
	(if result
		; if result is not #f return it
		result
		; else check if entity is an evaluation or predicate or schema
		(let ((type (cog-type entity)))
			(if (or (equal? type 'GroundedPredicateNode)
				   (equal? type 'DefinedPredicateNode))
				(set! result (cog-evaluate! (Evaluation entity (List)))))
			(if (equal? type 'PredicateNode)
				(set! result (cog-tv entity)))
			(if (or (equal? type 'GroundedSchemaNode)
                    (equal? type 'DefinedSchemaNode))
            	(set! result (cog-execute! (ExecutionOutput entity (List)))))
            (if (equal? type 'EvaluationLink)
                (set! result (cog-evaluate! entity)))
        )
	)
	result
)

(define (psi-get-number-value entity)
"
	Get the current value of psi-related entity and return as a number (rather
	than NumberNode).
	Todo: How to handle non-number returns. #f?
"
	(define result (psi-get-value entity))
	;(format #t "psi-get-number-value entity: \n~a initial result: ~a\n"
	;	entity result)
	(if (and (cog-atom? result) (eq? 'NumberNode (cog-type result)))
		(set! result (string->number (cog-name result))))
	; if result is a tv and confidenct is 0, means that it has not been set
	(if (and (cog-tv? result) (> (tv-conf result) 0))
		(set! result (tv-mean result)))
	(if (not (number? result))
		(set! result #f))
    ;(format #t "return result: ~a\n" result)
	result)


; OpenPsi entity current value representation types
(define statelink "StateLink")
(define evaluatable "Evaluatable")
(define executable "Executable")
(define evaluationlink "EvaluationLink") ; not sure if we need this yet
(define executionlink "ExecutionLink") ; ditto
(define undefined "Undefined")


(define (psi-set-value! entity value)
"
  Set the current numerical value of psi-related entity.

  entity - the object whose value is being set
  value - a numerical value (not NumberNode), assumed to be in [0,1] (for now)
"
	(define value-rep-type (psi-value-representation-type entity))
	(define representation) ; the atomese representation of the stored value

	;(format #t "\npsi-set-value! \n  entity: ~a  value: ~a  value-rep-type: ~a\n"
    ;		entity value value-rep-type)

	(set! representation
		(cond
			((equal? value-rep-type statelink) (State entity (Number value)))
			((equal? value-rep-type evaluatable)
			    (if (equal? (cog-type entity) 'PredicateNode)
			        ; If PredicateNode, then set node TV
			        (cog-set-tv! entity (stv value 1))
			        ; else wrap it in an EvaluationLink
			        ; Todo: this will probably need to be changed to handle
			        ; arguments.
				    (Evaluation entity (List) (stv value 1))))
			((equal? value-rep-type executable)
				(ExecutionOutput entity (List) (stv value 1)))
			(else (error (string-append "In psi-set-value! encountered undefined"
			    " value representation type: ") value-rep-type))))

	;(format #t "representation: ~a" representation)
)

(define psi-rep-type-node (Concept "value-representation-type"))

(define (psi-value-representation-type entity)
"
  Returns the representation type used to store the current value of entity.
  Potential return values: 'StateLink' 'Evaluatable' 'Executable'
  'Evaluation and ExecutionLink themselves?'

  Value representation type is stored in a StateLink:
        State
            List
                entity
                Concept 'value-representation-type'
            Concept '<the type for this entity>'
"
	;(define rep-type undefined)

	(define (set-value-rep-type! entity type)
		(State
            (List
                entity
                psi-rep-type-node)
            (Concept type)))

	; first see if representation type is already set for this entity
	(define rep-type (cog-get-state-value (List entity psi-rep-type-node)))

	;(format #t (string-append "\npsi-value-representation-type \n  entity: ~a  "
	;	"initial rep-type: ~a\n") entity rep-type)

	(if rep-type
		; return the stored representation type
		(cog-name rep-type)

		; else value representation type is not yet set
		;begin
		; Check if value is stored in StateLink, which is the default
		(if (eq? (tv-mean
			(cog-evaluate!
				(Satisfaction
					(State
						entity
						(Variable "$n"))))) 1)
			(begin
				(set-value-rep-type! entity statelink)
	            ;(format #t (string-append "Found value stored in SateLink. "
	            ;    "Setting value-rep type to ~a\n") statelink)
				;(set! rep-type statelink)
				; let's see if it will return from here
				statelink)

			; else check if entity is a predicate or schema
			(let ((atom-type (cog-type entity)))
				(if (or (equal? atom-type 'PredicateNode)
					   (equal? atom-type 'GroundedPredicateNode)
					   (equal? atom-type 'DefinedPredicateNode))
					(let ((confidence (tv-conf
							(cog-evaluate! (Evaluation entity (List))))))
						(if (not (eq? confidence 0))
							(begin
								(set-value-rep-type! entity evaluatable)
								(set! rep-type evaluatable)))))
				(if (or (equal? atom-type 'SchemaNode)
	                    (equal? atom-type 'GroundedSchemaNode)
	                    (equal? atom-type 'DefinedSchemaeNode))
	                (begin
	                    (set-value-rep-type! entity executable)
	                    (set! rep-type executable)))

	            ; Not sure if we need this for EvaluationLinks and
	            ; ExecutionLinks.
	            ;(if (equal? atom-type 'EvaluationLink)
	            ;    (begin (set-rep-type... ) (set! rep-type ...)))

	            ; If no current value is set for the entity, then set the value
	            ; type to statelink, which is the default
	            (if (not rep-type)
	                (begin
		                (set-value-rep-type! entity statelink)
		                (set! rep-type statelink)))
	            ;(format #t "Set value-rep type: ~a\n" rep-type)
	            rep-type))))
