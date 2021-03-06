(in-package :cmp)


#|
For sbcl
(sb-ext:restrict-compiler-policy 'debug 3)

|#

(defun try.attach-dispatch-blocks-to-clauses (clauses)
  "Get a list of clauses of the form '((exception var) code...) and
generate a block for each exception and return a list of conses of the blocks with the clauses.
eg: '(block ((exception var) code...))"
  (mapcar #'(lambda (x)
	      (cons (irc-basic-block-create "dispatch") x)) clauses))


(defun try.separate-clauses (clauses)
  "Separate out the normal clauses from the default clause"
  (let (cleanup-clause-body exception-clauses all-other-exceptions-clause)
    (dolist (clause clauses)
      (unless (consp (car clause))
	(error "Every with-try clause head must be wrapped in a list"))
      (let ((head (caar clause)))
	(cond
	  ((eq head 'cleanup) (setq cleanup-clause-body (cdr clause)))
	  ((eq head 'all-other-exceptions) (setq all-other-exceptions-clause clause))
	  (t (push clause exception-clauses)))))
    (when all-other-exceptions-clause
      (push all-other-exceptions-clause exception-clauses))
    (values cleanup-clause-body (nreverse exception-clauses))))



(defparameter *try.clause-stack* nil
  "Keep track of the nested try clauses")

(defun try.flatten (structure)
  (cond ((null structure ) nil)
	((atom structure) `(,structure))
	(t (mapcan #'try.flatten structure))))

(defun try.identify-all-unique-clause-types (all-clause-types)
  (let ((flattened-clause-types all-clause-types)
	unique-clause-types)
    (mapc #'(lambda (ct)
	      (if (member ct unique-clause-types)
		  nil
		  (push ct unique-clause-types)))
	  flattened-clause-types)
    unique-clause-types))



(defun try.add-landing-pad-clauses (landpad catch-clause-types)
  (let* ((types (reverse catch-clause-types))
	 (includes-all-other-exceptions (member 'all-other-exceptions types)))
    (mapc #'(lambda (ct)
	      (cond
		((eq ct 'all-other-exceptions)
		 nil ) ;; add the most general exception at the end
		(t
		 (irc-add-clause landpad (irc-get-or-create-global-i8*
					  (symbol-name ct) "GL-TYPE")))))
	  types)
    (when includes-all-other-exceptions
      (irc-add-clause landpad (llvm-sys:constant-pointer-null-get +i8*+)))
    ))





(defun try.one-dispatcher-and-handler (cur-dispatcher-block
				       next-dispatcher-block
				       clause
				       successful-catch-block
				       exn.slot ehselector.slot env)
  (let ((sel-gs (gensym "sel"))
	(typeid-gs (gensym "typeid"))
	(matches-type-gs (gensym "matches-type"))
	(handler-block-gs (gensym "handler-block"))
	(clause-type (caar clause))
	(clause-exception-name (cadr (car clause)))
	(clause-body (cdr clause))
	)
    (cond
      ((eq (caar clause) 'all-other-exceptions)
       `(progn
	  (irc-begin-block ,cur-dispatcher-block)
	  (with-catch (,exn.slot dummy-exception ,env)
	    ,@clause-body
	    ))
       )
      (t
       `(progn
	  (irc-begin-block ,cur-dispatcher-block)
	  (let* ((,sel-gs (irc-load ,ehselector.slot "ehselector-slot"))
		 (,typeid-gs (irc-call ,env "llvm.eh.typeid.for" (irc-get-or-create-global-i8* ,(symbol-name clause-type) "GL-TYPE")))
		 (,matches-type-gs (irc-icmp-eq ,sel-gs ,typeid-gs))
		 (,handler-block-gs (irc-basic-block-create ,(symbol-name handler-block-gs)))
		 )
;;	    (irc-call ,env "debugPrintI32" ,sel-gs)
;;	    (irc-call ,env "debugPrintI32" ,typeid-gs)
	    (irc-cond-br ,matches-type-gs ,handler-block-gs ,next-dispatcher-block)
	    (irc-begin-block ,handler-block-gs)
	    (with-catch (,exn.slot ,clause-exception-name ,env)
	      ,@clause-body)
	    (irc-branch-if-no-terminator-inst ,successful-catch-block) ;; Why is this commented out?
	    ))
       ))
    )
  )



(defmacro with-block-name-prefix ( &optional (prefix "") &rest body )
  `(let ((*block-name-prefix* ,prefix))
     ,@body))





(defmacro with-try (env code &rest catch-clauses)
  "with-try macro sets up exception handling for a block of code.
with-try creates one landing-pad that lists the exception clauses for this with-try block
and all other with-try blocks that this with-try is nested within.
WITH-TRY then sets up a chain of dispatchers that test if any exception that
lands at the landing pad match any of the catch-clauses and generates code for each of
the catch-clauses. If a catch-clause is evaluated then the flow drops out of the bottom
of the with-try.  The chain of dispatchers is connected to the chain of dispatchers
from the with-try that nests this with-try.
Cleanup code is codegen'd right after the CODE and just after the landing-pad instruction
just before any of the dispatchers.
A very important internal parameter is HIGHER-CLEANUP-BLOCK - this is a keyword symbol
that is used to store and lookup in the environment the next cleanup-block for passing
exceptions to higher levels of the code and unwinding the stack.

"
  (declare (optimize (debug 3) (safety 0) (speed 0)))
  (let ((HIGHER-CLEANUP-BLOCK-NAME :exception-handler-cleanup-block)
	(parent-cleanup-block-gs (gensym "parent-cleanup-block"))
	(parent-env-id-gs (gensym "parent-env-id"))
	(my-env-id-gs (gensym "my-env-id"))
	(landing-pad-block-gs (gensym "landing-pad-block"))
	(all-clause-types-gs (gensym "all-clause-types"))
	(unique-clause-types-gs (gensym "unique-clause-types"))
	(cont-block-gs (gensym "cont-block"))
	;;	(cleanup-block-gs (gensym "cleanup-block"))
	(landpad-gs (gensym "landingpad"))
;;	(clause-types-gs (gensym "clause-types"))
	(ehselector.slot-gs (gensym "ehselector.slot"))
	(dispatch-header-gs (gensym "dispatch-header"))
	;;	(cur-disp-block-gs (gensym "cur-disp-block"))
	;;	(cur-clause-gs (gensym "cur-clause"))
	(exn.slot-gs (gensym "exn.slot"))
	)
    (multiple-value-bind (cleanup-clause-body exception-clauses)
	(try.separate-clauses catch-clauses)
      (let* ((my-clause-types (mapcar #'caar exception-clauses))
	     (dispatcher-block-gensyms
	      (mapcar #'(lambda (x) (gensym (format nil "dispatch-~a-" (symbol-name (caar x)))))
		      exception-clauses))
	     (first-dispatcher-block-gs (car dispatcher-block-gensyms)))
	;;	     (cleanup-clause-list (cons cleanup-clause-body (make-list (- (length exception-clauses) 1)))))
	`(let ((,parent-env-id-gs (environment-id (get-parent-environment ,env)))
	       (,my-env-id-gs (environment-id ,env)))
	   (with-block-name-prefix (bformat nil "(TRY %d %d)." ,my-env-id-gs ,parent-env-id-gs)
;;	     (bformat t "Started with-try block my-env-id[%d]  parent-env-id[%d]\n" ,my-env-id-gs ,parent-env-id-gs)
	     (when (eql ,my-env-id-gs ,parent-env-id-gs)
	       (break "my-env-id is the same as parent-env-id!!!!"))
	     (irc-branch-to-and-begin-block (irc-basic-block-create "top"))
	     (let* ((,all-clause-types-gs (if ',my-clause-types
					      (append ',my-clause-types *exception-clause-types-to-handle*)
					      *exception-clause-types-to-handle*))
		    (*exception-clause-types-to-handle* ,all-clause-types-gs)
		    ;; Use *exception-handler-cleanup-block* rather than pulling the exception-handler-cleanup-block
		    ;; out of the environment
		    (,parent-cleanup-block-gs *exception-handler-cleanup-block*)
		    ;;		   #+(or)(,parent-cleanup-block-gs (lookup-metadata
		    ;;						    (get-parent-environment ,env)
		    ;;						    ,HIGHER-CLEANUP-BLOCK-NAME))

		    (,landing-pad-block-gs (irc-basic-block-create "landing-pad"))
		    (,dispatch-header-gs (irc-basic-block-create "dispatch-header"))
		    (,cont-block-gs (irc-basic-block-create "try-cont"))

		    ;; Use *exception-handler-cleanup-block* rather than the setf-metadata ,env ,HIGHER-CLEANUP-BLOCK-NAME below
		    (*exception-handler-cleanup-block* ,dispatch-header-gs )

		    )
	       (cmp-log "====>> In TRY%d --> parent-cleanup-block: %s\n" ,my-env-id-gs ,parent-cleanup-block-gs)
	       (let ,(mapcar #'(lambda (var-name)
				 (list var-name `(irc-basic-block-create ,(symbol-name var-name))))
			     dispatcher-block-gensyms)
;;		 #+(or) (setf-metadata ,env ,HIGHER-CLEANUP-BLOCK-NAME ,dispatch-header-gs)
;;		 #+(or) (setf-metadata ,env :exception-clause-types ',clause-types)
		 (with-landing-pad ,landing-pad-block-gs
		   ,code)
		 ,(when cleanup-clause-body
			`(progn
			   (irc-branch-to-and-begin-block (irc-basic-block-create "normal-cleanup"))
			   ,@cleanup-clause-body))
		 (irc-branch-if-no-terminator-inst ,cont-block-gs)
		 (irc-begin-landing-pad-block ,landing-pad-block-gs)
		 (let* ((,unique-clause-types-gs (try.identify-all-unique-clause-types ,all-clause-types-gs))
			(,landpad-gs (irc-create-landing-pad (length ,unique-clause-types-gs) "")))
		   (try.add-landing-pad-clauses ,landpad-gs ,unique-clause-types-gs)
		   (dbg-set-current-debug-location-here)
		   (irc-low-level-trace)
		   ,(when cleanup-clause-body
			  `(irc-set-cleanup ,landpad-gs t))
		   (multiple-value-bind (,exn.slot-gs ,ehselector.slot-gs)
		       (irc-preserve-exception-info ,env ,landpad-gs)
		     (irc-branch-to-and-begin-block ,dispatch-header-gs)
		     ,@(when cleanup-clause-body
			     cleanup-clause-body)
		     ,(if first-dispatcher-block-gs
			  `(irc-br ,first-dispatcher-block-gs)
			  `(irc-br ,parent-cleanup-block-gs))
		     ,@(maplist #'(lambda (cur-disp-block-gs cur-clause-gs)
				    (try.one-dispatcher-and-handler (car cur-disp-block-gs)
								    (if (cadr cur-disp-block-gs)
									(cadr cur-disp-block-gs)
									parent-cleanup-block-gs)
								    (car cur-clause-gs)
								    cont-block-gs
								    exn.slot-gs ehselector.slot-gs env)
				    )
				dispatcher-block-gensyms
				exception-clauses)
		     #|
		     ,(try.build-dispatchers-and-handlers result
		     dispatcher-block-gensyms
		     exception-clauses
		     cont-block-gs
		     exn.slot-gs ehselector.slot-gs env)
		     |#
		 ))
	     (irc-branch-if-no-terminator-inst ,cont-block-gs)
	     (irc-begin-block ,cont-block-gs)
	     )
	   )))))))




#|
;; Testing				; ; ; ; ; ; ; ; ;

		     (defparameter *irbuilder* '-*irbuilder*-)
		     (defparameter *the-module* '-*the-module*-)
		     (try-landing-pad-clauses 'landpad
'((("typeid_core_ReturnFrom" exception-ptr)
(try block-env
(irc-call block-env "blockHandleReturnFrom" result exception-ptr)
(default (try-rethrow)))))
'(try-rethrow))




		     (try.one-catch '(("typeid_core_ReturnFrom" exception-ptr) (DOSTUFF)) 'successful-catch-block 'ehselector-slot 'env)

		     (try.all-catches '((("typeid_core_ReturnFrom" exception-ptr) (DEAL-WITH-CATCH-RETURN-FROM))
(("typeid_core_Tagbody" exception-ptr) (DEAL-WITH-CATCH-TAGBODY)))
'(DEAL-WITH-CATCH-EVERYTHING)
'successful-catch-block
'ehselector-slot 'env)



		     (try.separate-clauses
'((("typeid_core_ReturnFrom" exception-ptr)
(try block-env
(irc-call block-env "blockHandleReturnFrom" result exception-ptr)
(default (try-rethrow))))
(default (try-rethrow))
))
 
		     (macroexpand
'(try. block-env
(codegen-progn result body block-env)
(("typeid_core_CatchThrow" exception-ptr)
(progn
(debug-print-i32 1001)
(debug-gdb env)
(try block-env
(irc-call block-env "catchIfTagMatchesStoreResultElseRethrow" result tag-unwind-store exception-ptr)
(default (irc-rethrow)))))
(default
(progn
(irc-call env "catchUnwind" tag-unwind-store)
(irc-rethrow env)))
(cleanup
(print "cleanup"))
))



		     (setq *print-right-margin* 130)
		     (setq *print-circle* nil)

		     (progn
(print (macroexpand '
(with-try block-env
(progn
(trace-enter-block-scope block-env `(block ,block-symbol ,body))
(codegen-progn result body block-env))
((typeid-core-return-from exception-ptr)
(HANDLE-RETURN-FROM))
((typeid-core-go exception-ptr)
(HANDLE-GO))
((cleanup) (DO-CLEANUP!!!!!!!!!!!))
))

)
nil)



		     (progn
(print (macroexpand '
(with-try block-env
(progn
(trace-enter-block-scope block-env `(block ,block-symbol ,body))
(codegen-progn result body block-env))
((typeid-core-return-from exception-ptr)
(HANDLE-RETURN-FROM))
))

)
nil)


		     (progn
(print (macroexpand '
(with-try block-env
(progn
(trace-enter-block-scope block-env `(block ,block-symbol ,body))
(codegen-progn result body block-env))
((cleanup) (DO-CLEANUP))
))

)
nil)


		     |#

