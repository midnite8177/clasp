
(in-package :cmp)
(export 'llvm-inline)

(defconstant +special-operator-dispatch+
  '(
    (progn . codegen-progn)
    (setq . codegen-setq )
    (let . codegen-let)
    (let* . codegen-let*)
    (if . codegen-if)
    (function .  codegen-function)
    (block .  codegen-block)
    (return-from .  codegen-return-from)
    (tagbody .  codegen-tagbody)
    (go .  codegen-go)
    (multiple-value-call .  codegen-multiple-value-call)
    (multiple-value-prog1 .  codegen-multiple-value-prog1)
    (flet .  codegen-flet)
    (labels .  codegen-labels)
    (eval-when .  codegen-eval-when)
    (the .  codegen-the)
    (core:truly-the .  codegen-truly-the)
    (locally .  codegen-locally)
    (quote .  codegen-quote)
    (throw .  codegen-throw)
    (unwind-protect .  codegen-unwind-protect)
    (catch .  codegen-catch)
    (macrolet .  codegen-macrolet)
    (dbg-i32 .  codegen-dbg-i32)
    (load-time-value .  codegen-load-time-value)
    (symbol-macrolet .  codegen-symbol-macrolet)
    (progv .  codegen-progv)
    (cmp:llvm-inline . codegen-llvm-inline)
    ))


(defun make-dispatch-table (alist)
  (let ((hash (make-hash-table :size (max 128 (* 2 (length alist))) :test #'eq)))
    (dolist (entry alist)
      (let ((name (car entry))
	    (function (cdr entry)))
	(core::hash-table-setf-gethash hash name function)))
    hash))

(defvar *special-operator-dispatch* (make-dispatch-table +special-operator-dispatch+))

#+debug-mps
(progn
  (bformat t "Dumping *special-operator-dispatch* = %s\n" *special-operator-dispatch*)
  (maphash #'(lambda (k v) (bformat t "Special operator = %s\n" k )) *special-operator-dispatch*))
