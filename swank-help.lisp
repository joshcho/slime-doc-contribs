(require :def-properties
         (pathname "/home/pollock/slime-doc-contribs/cl-def-properties/module.lisp"))

(defpackage :swank-help
  (:use :cl :alexandria :def-properties)
  (:export
   :read-emacs-symbol-info
   :read-emacs-package-info
   :read-emacs-system-info
   :read-emacs-packages-info
   :read-emacs-systems-info
   ;; my stuff
   :get-docs
   :get-external-functions
   :get-external-variables
   :all-packages))

(in-package :swank-help)

;; my stuff

(defun get-docs (sym)
  (documentation sym 'function))

(defun get-external-variables (package-name)
  (get-external-symbols #'boundp package-name))

(defun get-external-functions (package-name)
  (get-external-symbols #'fboundp package-name))

(defun get-external-symbols (pred package-name)
  "Retrieves all external symbols filtered by PRED from a package with PACKAGE-NAME."
  (declare ((or package string symbol) package-name))
  (the list
       (let ((lst (list))
             (package (find-package (string-upcase package-name))))
         (cond (package
                (do-external-symbols (symb package)
                  (when (and (funcall pred symb)
                             (eql (symbol-package symb) package))
                    (push symb lst)))
                lst)
               (t
                (error "~S does not designate a package" package-name))))))

(defun all-packages ()
  (mapcar (compose #'string-downcase #'package-name) (list-all-packages)))
;; original

(defun aget (alist key)
  (cdr (assoc key alist :test 'equalp)))

(defun sort-by-name (infos)
  (sort infos #'string< :key (lambda (info) (aget info :name))))

(defun info-for-emacs (info)
  (when (aget info :package)
    (setf (cdr (assoc :package info))
          (package-name (aget info :package))))
  (when (aget info :arglist)
    ;; arglist is conflictive for slime protocol. do not use.
    (setf (cdr (assoc :arglist info)) nil))
  (when (aget info :documentation)
    (push (cons :parsed-documentation
                (parse-docstring (aget info :documentation)
                                 (when (member (aget info :type) '(:function :generic-function :macro))
                                   (list-lambda-list-args
                                    (read-from-string (aget info :args))
                                    ))
                                 :package (find-package (aget info :package))))
          info))
  (push (cons :symbol (cdr (assoc :name info))) info)
  (setf (cdr (assoc :name info)) (symbol-name (cdr (assoc :name info))))
  info)

(defun read-emacs-symbol-info (symbol &optional kind shallow)
  (let ((infos (symbol-properties symbol shallow)))
    (if kind
        (alexandria:when-let ((info (find kind infos :key (lambda (info)
                                                            (aget info :type)))))
          (info-for-emacs info))
        (mapcar 'info-for-emacs infos))))

(defun read-emacs-package-info (package-name &optional shallow)
  (let ((package (or (and (typep package-name 'package)
                          package-name)
                     (find-package package-name)
                     (error "Package not found: ~a" package-name))))
    (list (cons :type :package)
          (cons :name (package-name package))
          (cons :documentation (documentation package t))
          (unless shallow
            (let (infos)
              (do-external-symbols (symbol package)
                (dolist (info (read-emacs-symbol-info symbol nil t))
                  (push info infos)))
              (cons :external-symbols (sort-by-name infos)))))))

(defun read-emacs-system-info (system-name &optional shallow)
  (let ((system (asdf:find-system system-name)))
    (list (cons :type :system)
          (cons :name system-name)
          (cons :documentation
                (slot-value system 'asdf/system::description)
                ;;(asdf:system-description system)
                )
          (cons :dependencies (remove-if-not 'stringp (asdf:system-depends-on system)))
          (cons :loaded-p (asdf:component-loaded-p system-name))
          (unless shallow
            (cons :packages (sort (mapcar 'package-name (asdf-system-packages system-name)) #'string<))))))

(defun read-emacs-packages-info ()
  (sort-by-name
   (mapcar (lambda (package)
             (read-emacs-package-info package t))
           (list-all-packages))))

(defun read-emacs-systems-info ()
  (sort-by-name
   (mapcar (lambda (system)
             (read-emacs-system-info system t))
           (asdf:registered-systems))))

(swank::defslimefun apropos-documentation-for-emacs
    (pattern &optional external-only case-sensitive package)
  "Make an apropos search in docstrings for Emacs.
The result is a list of property lists."
  (let ((package (if package
                     (or (swank::parse-package package)
                         (error "No such package: ~S" package)))))
    ;; The MAPCAN will filter all uninteresting symbols, i.e. those
    ;; who cannot be meaningfully described.
    (mapcan (swank::listify #'swank::briefly-describe-symbol-for-emacs)
            (sort (remove-duplicates
                   (apropos-symbols-documentation pattern external-only case-sensitive package))
                  #'swank::present-symbol-before-p))))

(defun some-documentation (symbol)
  (some (lambda (type)
          (documentation symbol type))
        '(function variable type structure set t)))

(defun apropos-symbols-documentation (pattern external-only case-sensitive package)
  (let ((packages (or package (remove (find-package :keyword)
                                      (list-all-packages))))
        (matcher (make-apropos-documentation-matcher pattern case-sensitive))
        (result))
    (with-package-iterator (next packages :external :internal)
      (loop (multiple-value-bind (morep symbol) (next)
              (cond ((not morep) (return))
                    ((and (if external-only (swank::symbol-external-p symbol) t)
                          (some-documentation symbol)
                          (funcall matcher (some-documentation symbol)))
                     (push symbol result))))))
    result))

(defun make-apropos-documentation-matcher (pattern case-sensitive)
  (let ((chr= (if case-sensitive #'char= #'char-equal)))
    (lambda (docstring)
      (every (lambda (word)
               (search word docstring :test chr=))
             (if (stringp pattern)
                 (list pattern)
                 pattern)))))

(provide :swank-help)
