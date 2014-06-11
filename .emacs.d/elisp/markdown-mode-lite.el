;;
;; Markdown mode lite
;;

(provide 'markdown-mode-lite)
;; I use markdown heavily for outlining. outline-magic provides handy functions for cycling the visibility
;; of subtrees, the same way org mode does it.
(require 'outline-magic)

(define-derived-mode markdown-lite-mode text-mode "Markdown-lite"
  ;; TODO(philc): RE-enable some of these.
  "Major mode for editing Markdown files."
  ;; Natural Markdown tab width
  (setq tab-width 4)
  ;; Comments
  (make-local-variable 'comment-start)
  (setq comment-start "<!-- ")
  (make-local-variable 'comment-end)
  (setq comment-end " -->")
  (make-local-variable 'comment-start-skip)
  (setq comment-start-skip "<!--[ \t]*")
  (make-local-variable 'comment-column)
  (setq comment-column 0)
  (set (make-local-variable 'comment-auto-fill-only-comments) nil)
  ;; Font lock.
  (set (make-local-variable 'markdown-mode-font-lock-keywords) nil)
  (set (make-local-variable 'font-lock-defaults) nil)
  (set (make-local-variable 'font-lock-multiline) t)
  ;; TODO(philc): re-fontifys buffer
  ;; (markdown-reload-extensions)

  ;; Extensions
  (make-local-variable 'markdown-enable-math)
  (add-hook 'hack-local-variables-hook 'markdown-reload-extensions)
  ;; For imenu support
  ;; (setq imenu-create-index-function 'markdown-imenu-create-index)
  ;; For menu support in XEmacs
  ;; (easy-menu-add markdown-mode-menu markdown-mode-map)
  ;; Defun movement
  ;; (set (make-local-variable 'beginning-of-defun-function)
  ;;      'markdown-beginning-of-defun)
  ;; (set (make-local-variable 'end-of-defun-function)
  ;;      'markdown-end-of-defun)
  ;; Paragraph filling
  (set (make-local-variable 'paragraph-start)
       "\f\\|[ \t]*$\\|[ \t]*[*+-] \\|[ \t]*[0-9]+\\.[ \t]\\|[ \t]*: ")
  (set (make-local-variable 'paragraph-separate)
       "\\(?:[ \t\f]*\\|.*  \\)$")
  (set (make-local-variable 'adaptive-fill-first-line-regexp)
       "\\`[ \t]*>[ \t]*?\\'")

  (set (make-local-variable 'adaptive-fill-function)
       'markdown-adaptive-fill-function)

  ;; Outline mode
  (make-local-variable 'outline-regexp)
  ;; (setq outline-regexp markdown-regex-header)
  ;; markdown-mode has support for outline mode, but the implementations is that headings are folded. For my
  ;; purposes, I like instead to fold subtrees of lists.
  (setq outline-regexp "[ ]*\\*") ; matches a leading bullet point

  (make-local-variable 'outline-level)
  (setq outline-level 'lisp-outline-level)
  ;; (setq outline-level 'markdown-outline-level)

  ;; Cause use of ellipses for invisible text.
  ;; (add-to-invisibility-spec '(outline . t))
  ;; Indentation and filling
  (make-local-variable 'fill-nobreak-predicate)
  (add-hook 'fill-nobreak-predicate 'markdown-nobreak-p)
  ;; (setq indent-line-function markdown-indent-function)

  ;; Prepare hooks for XEmacs compatibility
  (when (featurep 'xemacs)
    (make-local-hook 'after-change-functions)
    (make-local-hook 'font-lock-extend-region-functions)
    (make-local-hook 'window-configuration-change-hook))

  ;; Multiline font lock
  (add-hook 'font-lock-extend-region-functions
            'markdown-font-lock-extend-region)

  ;; Anytime text changes make sure it gets fontified correctly
  ;; (add-hook 'after-change-functions 'markdown-check-change-for-wiki-link t t)

  ;; If we left the buffer there is a really good chance we were
  ;; creating one of the wiki link documents. Make sure we get
  ;; refontified when we come back.
  ;; (add-hook 'window-configuration-change-hook
  ;;           'markdown-fontify-buffer-wiki-links t t)

  ;; do the initial link fontification
  ;; (markdown-fontify-buffer-wiki-links)
  )

(add-to-list 'auto-mode-alist '("\\.markdown$" . markdown-lite-mode))
(add-to-list 'auto-mode-alist '("\\.md$" . markdown-lite-mode))

(defun markdown-insert-list-item-below ()
  "Inserts a new list item under the current one. markdown-insert-list-item inserts above, by default."
  (interactive)
  (end-of-line)
  (call-interactively 'markdown-insert-list-item)
  (evil-append nil))

(defun insert-markdown-setext-header (setext-type)
  "With the cursor focused on the header's text, insert a setext header line below that text.
   setet-string: either '==' or '--'"
  (let* ((line-length (length (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
         (setext-str (make-string line-length (get-byte 0 setext-type))))
    (end-of-line)
    (insert (concat "\n" setext-str))))

(defun preview-markdown ()
  "Pipes the buffer's contents into a script which renders the markdown as HTML and opens in a browser."
  (interactive)
  ;; NOTE(philc): line-number-at-pos is 1-indexed.
  (let ((command (format "markdown_page.rb --scroll-to-line %s | browser" (- (line-number-at-pos) 1))))
    (call-process-region (point-min) (point-max) "/bin/bash" nil nil nil "-c" command)))

(defun markdown-get-list-item-region ()
  "Returns '(start, end) for the markdown list item under the cursor, excluding subtrees."
  (interactive)
  (save-excursion
    (let ((start (line-beginning-position))
          (end (line-end-position))
          (end-of-file nil))
      ; NOTE(philc): (next-line) returns an error if we're at the end of the file.
      (ignore-errors (next-line))
      ;; Stop the search at left-aligned text (which is an approximation for detecting headings).
      (while (not (or ; (string/blank? (util/get-current-line)) ; TODO(philc): Remove this.
                   end-of-file
                   (string-match "^[ ]*\\*" (util/get-current-line))
                   (string-match "^[^ *]" (util/get-current-line))))
        (setq end (line-end-position))
        (condition-case nil (next-line) (error (setq end-of-file t))))
      (list start end))))

(defun markdown-perform-promote (should-promote)
  "Promotes the list item under the cursor, excluding subtrees"
  (let* ((region (markdown-get-list-item-region))
         (indent-amount (if should-promote -2 2)))
    (indent-rigidly (first region) (second region) indent-amount)))

(defun markdown-perform-promote-subtree (should-promote)
  "Promotes hte list under under the cursor, and also promotes all subtrees."
  ;; This show-subtree call is important because this indentation code does not work with collapsed subtrees.
  ;; They are converted into raw ellipses characters, and so their contents would otherwise b elost.
  (show-subtree)
  (let* ((line (util/get-current-line))
         (start-level (util/line-indentation-level line))
         (indent-amount (if should-promote -2 2))
         (indent-fn (lambda ()
                      (indent-rigidly (line-beginning-position) (line-end-position) indent-amount))))
    (save-excursion
      (funcall indent-fn)
      (next-line)
      (while (and (setq line (util/get-current-line))
                  (or (string/blank? line)
                      (> (util/line-indentation-level line) start-level)))
        (when (not (string/blank? line))
          (funcall indent-fn))
        (next-line)))))

(defun markdown-promote () (interactive) (markdown-perform-promote t))
(defun markdown-demote () (interactive) (markdown-perform-promote nil))
(defun markdown-promote-subtree () (interactive) (markdown-perform-promote-subtree t))
(defun markdown-demote-subtree () (interactive) (markdown-perform-promote-subtree nil))

(defun setup-markdown-mode ()
  (interactive)
  (evil-define-key 'normal markdown-lite-mode-map
    ";l" 'markdown-cleanup-list-numbers
    ";vv" 'preview-markdown)

  (define-key markdown-lite-mode-map (kbd "<tab>") nil) ; Normally bound to markdown-cycle.

  (evil-define-key 'normal markdown-lite-mode-map
    ;; Autocomplete setext headers by typing "==" or "--" on the header's line in normal mode.
    (kbd "==") '(lambda () (interactive) (insert-markdown-setext-header "=="))
    (kbd "--") '(lambda () (interactive) (insert-markdown-setext-header "--"))
    (kbd "TAB") '(lambda () (interactive) (save-excursion (outline-cycle)))
    (kbd "C-S-L") 'markdown-demote
    (kbd "C-S-H") 'markdown-promote)
  (evil-define-key 'insert markdown-lite-mode-map
    (kbd "C-S-H") 'markdown-promote
    (kbd "C-S-L") 'markdown-demote)
  (mapc (lambda (state)
          (evil-define-key state markdown-lite-mode-map
            (kbd "C-S-K") 'markdown-move-list-item-up
            (kbd "C-S-J") 'markdown-move-list-item-down
            ;; M-return creates a new todo item and enters insert mode.
            (kbd "<C-return>") 'markdown-insert-list-item-below))
        '(normal insert)))

(setup-markdown-mode)

;;
;; Code taken from markdown-mode.el.
;;

(defconst markdown-regex-list
  "^\\([ \t]*\\)\\([0-9]+\\.\\|[\\*\\+-]\\)\\([ \t]+\\)"
  "Regular expression for matching list items.")

(defconst markdown-regex-code
  "\\(\\`\\|[^\\]\\)\\(\\(`+\\)\\(\\(.\\|\n[^\n]\\)*?[^`]\\)\\3\\)\\([^`]\\|\\'\\)"
  "Regular expression for matching inline code fragments.

The first group ensures that the leading backquote character
is not escaped.  The group \\(.\\|\n[^\n]\\) matches any
character, including newlines, but not two newlines in a row.
The final group requires that the character following the code
fragment is not a backquote.")

(defconst markdown-regex-pre
  "^\\(    \\|\t\\).*$"
  "Regular expression for matching preformatted text sections.")

(defconst markdown-regex-line-break
  "[^ \n\t][ \t]*\\(  \\)$"
  "Regular expression for matching line breaks.")

(defconst markdown-regex-blockquote
  "^[ \t]*\\(>\\).*$"
  "Regular expression for matching blockquote lines.")

(defconst markdown-regex-block-separator
  "\\(\\`\\|\\(\n[ \t]*\n\\)[^\n \t]\\)"
  "Regular expression for matching block boundaries.")

(defconst markdown-regex-header
  "^\\(?:\\(.+\\)\n\\(=+\\)\\|\\(.+\\)\n\\(-+\\)\\|\\(#+\\)\\s-*\\(.*?\\)\\s-*?\\(#*\\)\\)$"
  "Regexp identifying Markdown headers.")

(defconst markdown-regex-header-1-atx
  "^\\(#\\)[ \t]*\\(.+?\\)[ \t]*\\(#*\\)$"
  "Regular expression for level 1 atx-style (hash mark) headers.")

(defconst markdown-regex-header-2-atx
  "^\\(##\\)[ \t]*\\(.+?\\)[ \t]*\\(#*\\)$"
  "Regular expression for level 2 atx-style (hash mark) headers.")

(defconst markdown-regex-header-3-atx
  "^\\(###\\)[ \t]*\\(.+?\\)[ \t]*\\(#*\\)$"
  "Regular expression for level 3 atx-style (hash mark) headers.")

(defconst markdown-regex-header-4-atx
  "^\\(####\\)[ \t]*\\(.+?\\)[ \t]*\\(#*\\)$"
  "Regular expression for level 4 atx-style (hash mark) headers.")

(defconst markdown-regex-header-5-atx
  "^\\(#####\\)[ \t]*\\(.+?\\)[ \t]*\\(#*\\)$"
  "Regular expression for level 5 atx-style (hash mark) headers.")

(defconst markdown-regex-header-6-atx
  "^\\(######\\)[ \t]*\\(.+?\\)[ \t]*\\(#*\\)$"
  "Regular expression for level 6 atx-style (hash mark) headers.")

(defconst markdown-regex-header-1-setext
  "^\\(.*\\)\n\\(=+\\)$"
  "Regular expression for level 1 setext-style (underline) headers.")

(defconst markdown-regex-header-2-setext
  "^\\(.*\\)\n\\(-+\\)$"
  "Regular expression for level 2 setext-style (underline) headers.")

(defconst markdown-regex-header-setext
  "^\\(.+\\)\n\\(\\(?:=\\|-\\)+\\)$"
  "Regular expression for generic setext-style (underline) headers.")

(defconst markdown-regex-header-atx
  "^\\(#+\\)[ \t]*\\(.*?\\)[ \t]*\\(#*\\)$"
  "Regular expression for generic atx-style (hash mark) headers.")

;; (defconst markdown-regex-line-break
;;   "[^ \n\t][ \t]*\\(  \\)$"
;;   "Regular expression for matching line breaks.")

(defun markdown-insert-list-item (&optional arg)
  "Insert a new list item.
If the point is inside unordered list, insert a bullet mark.  If
the point is inside ordered list, insert the next number followed
by a period.  Use the previous list item to determine the amount
of whitespace to place before and after list markers.

With a \\[universal-argument] prefix (i.e., when ARG is (4)),
decrease the indentation by one level.

With two \\[universal-argument] prefixes (i.e., when ARG is (16)),
increase the indentation by one level."
  (interactive "p")
  (let (bounds item-indent marker indent new-indent new-loc)
    (save-match-data
      ;; Look for a list item on current or previous non-blank line
      (save-excursion
        (while (and (not (setq bounds (markdown-cur-list-item-bounds)))
                    (not (bobp))
                    (markdown-cur-line-blank-p))
          (forward-line -1)))
      (when bounds
        (cond ((save-excursion
                 (skip-chars-backward " \t")
                 (looking-at markdown-regex-list))
               (beginning-of-line)
               (insert "\n")
               (forward-line -1))
              ((not (markdown-cur-line-blank-p))
               (newline)))
        (setq new-loc (point)))
      ;; Look ahead for a list item on next non-blank line
      (unless bounds
        (save-excursion
          (while (and (null bounds)
                      (not (eobp))
                      (markdown-cur-line-blank-p))
            (forward-line)
            (setq bounds (markdown-cur-list-item-bounds))))
        (when bounds
          (setq new-loc (point))
          (unless (markdown-cur-line-blank-p)
            (newline))))
      (if (not bounds)
          ;; When not in a list, start a new unordered one
          (progn
            (unless (markdown-cur-line-blank-p)
              (insert "\n"))
            (insert "* "))
        ;; Compute indentation for a new list item
        (setq item-indent (nth 2 bounds))
        (setq marker (nth 4 bounds))
        (setq indent (cond
                      ((= arg 4) (max (- item-indent 4) 0))
                      ((= arg 16) (+ item-indent 4))
                      (t item-indent)))
        (setq new-indent (make-string indent 32))
        (goto-char new-loc)
        (cond
         ;; Ordered list
         ((string-match "[0-9]" marker)
          (if (= arg 16) ;; starting a new column indented one more level
              (insert (concat new-indent "1. "))
            ;; travel up to the last item and pick the correct number.  If
            ;; the argument was nil, "new-indent = item-indent" is the same,
            ;; so we don't need special treatment. Neat.
            (save-excursion
              (while (not (looking-at (concat new-indent "\\([0-9]+\\)\\.")))
                (forward-line -1)))
            (insert (concat new-indent
                            (int-to-string (1+ (string-to-number (match-string 1))))
                            ". "))))
         ;; Unordered list
         ((string-match "[\\*\\+-]" marker)
          (insert new-indent marker)))))))

(defun markdown-move-list-item-up ()
  "Move the current list item up in the list when possible."
  (interactive)
  (let (cur prev old)
    (when (setq cur (markdown-cur-list-item-bounds))
      (setq old (point))
      (goto-char (nth 0 cur))
      (if (markdown-prev-list-item (nth 3 cur))
          (progn
            (setq prev (markdown-cur-list-item-bounds))
            (condition-case nil
                (progn
                  (transpose-regions (nth 0 prev) (nth 1 prev)
                                     (nth 0 cur) (nth 1 cur) t)
                  (goto-char (+ (nth 0 prev) (- old (nth 0 cur)))))
              ;; Catch error in case regions overlap.
              (error (goto-char old))))
        (goto-char old)))))

(defun markdown-move-list-item-down ()
  "Move the current list item down in the list when possible."
  (interactive)
  (let (cur next old)
    (when (setq cur (markdown-cur-list-item-bounds))
      (setq old (point))
      (if (markdown-next-list-item (nth 3 cur))
          (progn
            (setq next (markdown-cur-list-item-bounds))
            (condition-case nil
                (progn
                  (transpose-regions (nth 0 cur) (nth 1 cur)
                                     (nth 0 next) (nth 1 next) nil)
                  (goto-char (+ old (- (nth 1 next) (nth 1 cur)))))
              ;; Catch error in case regions overlap.
              (error (goto-char old))))
        (goto-char old)))))

(defun markdown-prev-list-item (level)
  "Search backward from point for a list item with indentation LEVEL.
Set point to the beginning of the item, and return point, or nil
upon failure."
  (let (bounds indent prev)
    (setq prev (point))
    (forward-line -1)
    (setq indent (markdown-cur-line-indent))
    (while
        (cond
         ;; Stop at beginning of buffer
         ((bobp) (setq prev nil))
         ;; Continue if current line is blank
         ((markdown-cur-line-blank-p) t)
         ;; List item
         ((and (looking-at markdown-regex-list)
               (setq bounds (markdown-cur-list-item-bounds)))
          (cond
           ;; Continue at item with greater indentation
           ((> (nth 3 bounds) level) t)
           ;; Stop and return point at item of equal indentation
           ((= (nth 3 bounds) level)
            (setq prev (point))
            nil)
           ;; Stop and return nil at item with lesser indentation
           ((< (nth 3 bounds) level)
            (setq prev nil)
            nil)))
         ;; Continue while indentation is the same or greater
         ((>= indent level) t)
         ;; Stop if current indentation is less than list item
         ;; and the next is blank
         ((and (< indent level)
               (markdown-next-line-blank-p))
          (setq prev nil))
         ;; Stop at a header
         ((looking-at markdown-regex-header) (setq prev nil))
         ;; Stop at a horizontal rule
         ((looking-at markdown-regex-hr) (setq prev nil))
         ;; Otherwise, continue.
         (t t))
      (forward-line -1)
      (setq indent (markdown-cur-line-indent)))
    prev))

(defun markdown-next-list-item (level)
  "Search forward from point for the next list item with indentation LEVEL.
Set point to the beginning of the item, and return point, or nil
upon failure."
  (let (bounds indent prev next)
    (setq next (point))
    (forward-line)
    (setq indent (markdown-cur-line-indent))
    (while
        (cond
         ;; Stop at end of the buffer.
         ((eobp) (setq prev nil))
         ;; Continue if the current line is blank
         ((markdown-cur-line-blank-p) t)
         ;; List item
         ((and (looking-at markdown-regex-list)
               (setq bounds (markdown-cur-list-item-bounds)))
          (cond
           ;; Continue at item with greater indentation
           ((> (nth 3 bounds) level) t)
           ;; Stop and return point at item of equal indentation
           ((= (nth 3 bounds) level)
            (setq next (point))
            nil)
           ;; Stop and return nil at item with lesser indentation
           ((< (nth 3 bounds) level)
            (setq next nil)
            nil)))
         ;; Continue while indentation is the same or greater
         ((>= indent level) t)
         ;; Stop if current indentation is less than list item
         ;; and the previous line was blank.
         ((and (< indent level)
               (markdown-prev-line-blank-p))
          (setq next nil))
         ;; Stop at a header
         ((looking-at markdown-regex-header) (setq next nil))
         ;; Stop at a horizontal rule
         ((looking-at markdown-regex-hr) (setq next nil))
         ;; Otherwise, continue.
         (t t))
      (forward-line)
      (setq indent (markdown-cur-line-indent)))
    next))

(defun markdown-cur-list-item-bounds ()
  "Return bounds and indentation of the current list item.
Return a list of the form (begin end indent nonlist-indent marker).
If the point is not inside a list item, return nil.
Leave match data intact for `markdown-regex-list'."
  (let (cur prev-begin prev-end indent nonlist-indent marker)
    ;; Store current location
    (setq cur (point))
    ;; Verify that cur is between beginning and end of item
    (save-excursion
      (end-of-line)
      (when (re-search-backward markdown-regex-list nil t)
        (setq prev-begin (match-beginning 0))
        (setq indent (length (match-string 1)))
        (setq nonlist-indent (length (match-string 0)))
        (setq marker (concat (match-string 2) (match-string 3)))
        (save-match-data
          (markdown-cur-list-item-end nonlist-indent)
          (setq prev-end (point)))
        (when (and (>= cur prev-begin)
                   (<= cur prev-end)
                   nonlist-indent)
          (list prev-begin prev-end indent nonlist-indent marker))))))

(defun markdown-cur-list-item-end (level)
  "Move to the end of the current list item with nonlist indentation LEVEL.
If the point is not in a list item, do nothing."
  (let (indent)
    (forward-line)
    (setq indent (markdown-cur-line-indent))
    (while
        (cond
         ;; Stop at end of the buffer.
         ((eobp) nil)
         ;; Continue if the current line is blank
         ((markdown-cur-line-blank-p) t)
         ;; Continue while indentation is the same or greater
         ((>= indent level) t)
         ;; Stop if current indentation is less than list item
         ;; and the previous line was blank.
         ((and (< indent level)
               (markdown-prev-line-blank-p))
          nil)
         ;; Stop at a new list item of the same or lesser indentation
         ((looking-at markdown-regex-list) nil)
         ;; Stop at a header
         ((looking-at markdown-regex-header) nil)
         ;; Stop at a horizontal rule
         ;; ((looking-at markdown-regex-hr) nil)
         ;; Otherwise, continue.
         (t t))
      (forward-line)
      (setq indent (markdown-cur-line-indent)))
    ;; Don't skip over whitespace for empty list items (marker and
    ;; whitespace only), just move to end of whitespace.
    (if (looking-back (concat markdown-regex-list "\\s-*"))
          (goto-char (match-end 3))
      (skip-syntax-backward "-"))))

(defun markdown-cur-line-blank-p ()
  "Return t if the current line is blank and nil otherwise."
  (save-excursion
    (beginning-of-line)
    (re-search-forward "^\\s *$" (line-end-position) t)))

(defun markdown-font-lock-extend-region ()
  "Extend the search region to include an entire block of text.
This helps improve font locking for block constructs such as pre blocks."
  ;; Avoid compiler warnings about these global variables from font-lock.el.
  ;; See the documentation for variable `font-lock-extend-region-functions'.
  (eval-when-compile (defvar font-lock-beg) (defvar font-lock-end))
  (save-excursion
    (goto-char font-lock-beg)
    (unless (looking-back "\n\n")
      (let ((found (or (re-search-backward "\n\n" nil t) (point-min))))
        (goto-char font-lock-end)
        (when (re-search-forward "\n\n" nil t)
          (setq font-lock-end (match-beginning 0))
          (setq font-lock-beg found))))))

(defun markdown-nobreak-p ()
  "Return nil if it is acceptable to break the current line at the point."
  ;; inside in square brackets (e.g., link anchor text)
  (looking-back "\\[[^]]*"))

(defun markdown-adaptive-fill-function ()
  "Return prefix for filling paragraph or nil if not determined."
  (cond
   ;; List item inside blockquote
   ((looking-at "^[ \t]*>[ \t]*\\([0-9]+\\.\\|[*+-]\\)[ \t]+")
    (replace-regexp-in-string
     "[0-9\\.*+-]" " " (match-string-no-properties 0)))
   ;; Blockquote
   ((looking-at "^[ \t]*>[ \t]*")
    (match-string-no-properties 0))
   ;; List items
   ((looking-at markdown-regex-list)
    (match-string-no-properties 0))
   ;; No match
   (t nil)))

(defvar markdown-mode-font-lock-keywords nil
  "Default highlighting expressions for Markdown mode.
This variable is defined as a buffer-local variable for dynamic
extension support.")

;; (defcustom markdown-indent-function 'markdown-indent-line
;;   "Function to use to indent."
;;   :group 'markdown
;;   :type 'function)

(defvar markdown-lite-mode-map
  "Keymap for Markdown lite major mode."
  (let ((map (make-keymap)))
    ;; (define-key map (kbd "<backspace>") 'markdown-exdent-or-delete)
    ;; (define-key map (kbd "<tab>") 'markdown-cycle)
    map))

(defun markdown-cur-line-indent ()
  "Return the number of leading whitespace characters in the current line."
  (save-match-data
    (save-excursion
      (goto-char (line-beginning-position))
      (re-search-forward "^[ \t]+" (line-end-position) t)
      (current-column))))

(defun markdown-prev-line-blank-p ()
  "Return t if the previous line is blank and nil otherwise.
If we are at the first line, then consider the previous line to be blank."
  (or (= (line-beginning-position) (point-min))
      (save-excursion
        (forward-line -1)
        (markdown-cur-line-blank-p))))


;;; Font Lock =================================================================

(require 'font-lock)

(defvar markdown-italic-face 'markdown-italic-face
  "Face name to use for italic text.")

(defvar markdown-bold-face 'markdown-bold-face
  "Face name to use for bold text.")

(defvar markdown-header-delimiter-face 'markdown-header-delimiter-face
  "Face name to use as a base for header delimiters.")

(defvar markdown-header-rule-face 'markdown-header-rule-face
  "Face name to use as a base for header rules.")

(defvar markdown-header-face 'markdown-header-face
  "Face name to use as a base for headers.")

(defvar markdown-header-face-1 'markdown-header-face-1
  "Face name to use for level-1 headers.")

(defvar markdown-header-face-2 'markdown-header-face-2
  "Face name to use for level-2 headers.")

(defvar markdown-header-face-3 'markdown-header-face-3
  "Face name to use for level-3 headers.")

(defvar markdown-header-face-4 'markdown-header-face-4
  "Face name to use for level-4 headers.")

(defvar markdown-header-face-5 'markdown-header-face-5
  "Face name to use for level-5 headers.")

(defvar markdown-header-face-6 'markdown-header-face-6
  "Face name to use for level-6 headers.")

(defvar markdown-inline-code-face 'markdown-inline-code-face
  "Face name to use for inline code.")

(defvar markdown-list-face 'markdown-list-face
  "Face name to use for list markers.")

(defvar markdown-blockquote-face 'markdown-blockquote-face
  "Face name to use for blockquote.")

(defvar markdown-pre-face 'markdown-pre-face
  "Face name to use for preformatted text.")

(defvar markdown-language-keyword-face 'markdown-language-keyword-face
  "Face name to use for programming language identifiers.")

(defvar markdown-link-face 'markdown-link-face
  "Face name to use for links.")

(defvar markdown-missing-link-face 'markdown-missing-link-face
  "Face name to use for links where the linked file does not exist.")

(defvar markdown-reference-face 'markdown-reference-face
  "Face name to use for reference.")

(defvar markdown-footnote-face 'markdown-footnote-face
  "Face name to use for footnote identifiers.")

(defvar markdown-url-face 'markdown-url-face
  "Face name to use for URLs.")

(defvar markdown-link-title-face 'markdown-link-title-face
  "Face name to use for reference link titles.")

(defvar markdown-line-break-face 'markdown-line-break-face
  "Face name to use for hard line breaks.")

(defvar markdown-comment-face 'markdown-comment-face
  "Face name to use for HTML comments.")

(defvar markdown-math-face 'markdown-math-face
  "Face name to use for LaTeX expressions.")

(defvar markdown-metadata-key-face 'markdown-metadata-key-face
  "Face name to use for metadata keys.")

(defvar markdown-metadata-value-face 'markdown-metadata-value-face
  "Face name to use for metadata values.")

(defgroup markdown-faces nil
  "Faces used in Markdown Mode"
  :group 'markdown
  :group 'faces)

(defface markdown-italic-face
  '((t (:inherit font-lock-variable-name-face :slant italic)))
  "Face for italic text."
  :group 'markdown-faces)

(defface markdown-bold-face
  '((t (:inherit font-lock-variable-name-face :weight bold)))
  "Face for bold text."
  :group 'markdown-faces)

(defface markdown-header-rule-face
  '((t (:inherit font-lock-function-name-face :weight bold)))
  "Base face for headers rules."
  :group 'markdown-faces)

(defface markdown-header-delimiter-face
  '((t (:inherit font-lock-function-name-face :weight bold)))
  "Base face for headers hash delimiter."
  :group 'markdown-faces)

(defface markdown-header-face
  '((t (:inherit font-lock-function-name-face :weight bold)))
  "Base face for headers."
  :group 'markdown-faces)

(defface markdown-header-face-1
  '((t (:inherit markdown-header-face)))
  "Face for level-1 headers."
  :group 'markdown-faces)

(defface markdown-header-face-2
  '((t (:inherit markdown-header-face)))
  "Face for level-2 headers."
  :group 'markdown-faces)

(defface markdown-header-face-3
  '((t (:inherit markdown-header-face)))
  "Face for level-3 headers."
  :group 'markdown-faces)

(defface markdown-header-face-4
  '((t (:inherit markdown-header-face)))
  "Face for level-4 headers."
  :group 'markdown-faces)

(defface markdown-header-face-5
  '((t (:inherit markdown-header-face)))
  "Face for level-5 headers."
  :group 'markdown-faces)

(defface markdown-header-face-6
  '((t (:inherit markdown-header-face)))
  "Face for level-6 headers."
  :group 'markdown-faces)

(defface markdown-inline-code-face
  '((t (:inherit font-lock-constant-face)))
  "Face for inline code."
  :group 'markdown-faces)

(defface markdown-list-face
  '((t (:inherit font-lock-builtin-face)))
  "Face for list item markers."
  :group 'markdown-faces)

(defface markdown-blockquote-face
  '((t (:inherit font-lock-doc-face)))
  "Face for blockquote sections."
  :group 'markdown-faces)

(defface markdown-pre-face
  '((t (:inherit font-lock-constant-face)))
  "Face for preformatted text."
  :group 'markdown-faces)

(defface markdown-language-keyword-face
  '((t (:inherit font-lock-type-face)))
  "Face for programming language identifiers."
  :group 'markdown-faces)

(defface markdown-link-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for links."
  :group 'markdown-faces)

(defface markdown-missing-link-face
  '((t (:inherit font-lock-warning-face)))
  "Face for missing links."
  :group 'markdown-faces)

(defface markdown-reference-face
  '((t (:inherit font-lock-type-face)))
  "Face for link references."
  :group 'markdown-faces)

(defface markdown-footnote-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for footnote markers."
  :group 'markdown-faces)

(defface markdown-url-face
  '((t (:inherit font-lock-string-face)))
  "Face for URLs."
  :group 'markdown-faces)

(defface markdown-link-title-face
  '((t (:inherit font-lock-comment-face)))
  "Face for reference link titles."
  :group 'markdown-faces)

(defface markdown-line-break-face
  '((t (:inherit font-lock-constant-face :underline t)))
  "Face for hard line breaks."
  :group 'markdown-faces)

(defface markdown-comment-face
  '((t (:inherit font-lock-comment-face)))
  "Face for HTML comments."
  :group 'markdown-faces)

(defface markdown-math-face
  '((t (:inherit font-lock-string-face)))
  "Face for LaTeX expressions."
  :group 'markdown-faces)

(defface markdown-metadata-key-face
  '((t (:inherit font-lock-variable-name-face)))
  "Face for metadata keys."
  :group 'markdown-faces)

(defface markdown-metadata-value-face
  '((t (:inherit font-lock-string-face)))
  "Face for metadata values."
  :group 'markdown-faces)

(defvar markdown-mode-font-lock-keywords-basic
  (list
   (cons 'markdown-match-pre-blocks '((0 markdown-pre-face)))
   (cons 'markdown-match-fenced-code-blocks '((0 markdown-pre-face)))
   ;; (cons markdown-regex-blockquote 'markdown-blockquote-face)
   (cons markdown-regex-header-1-setext '((1 markdown-header-face-1)
                                          (2 markdown-header-rule-face)))
   (cons markdown-regex-header-2-setext '((1 markdown-header-face-2)
                                          (2 markdown-header-rule-face)))
   (cons markdown-regex-header-6-atx '((1 markdown-header-delimiter-face)
                                       (2 markdown-header-face-6)
                                       (3 markdown-header-delimiter-face)))
   (cons markdown-regex-header-5-atx '((1 markdown-header-delimiter-face)
                                       (2 markdown-header-face-5)
                                       (3 markdown-header-delimiter-face)))
   (cons markdown-regex-header-4-atx '((1 markdown-header-delimiter-face)
                                       (2 markdown-header-face-4)
                                       (3 markdown-header-delimiter-face)))
   (cons markdown-regex-header-3-atx '((1 markdown-header-delimiter-face)
                                       (2 markdown-header-face-3)
                                       (3 markdown-header-delimiter-face)))
   (cons markdown-regex-header-2-atx '((1 markdown-header-delimiter-face)
                                       (2 markdown-header-face-2)
                                       (3 markdown-header-delimiter-face)))
   (cons markdown-regex-header-1-atx '((1 markdown-header-delimiter-face)
                                       (2 markdown-header-face-1)
                                       (3 markdown-header-delimiter-face)))
   ;; (cons 'markdown-match-multimarkdown-metadata '((1 markdown-metadata-key-face)
   ;;                                                (2 markdown-metadata-value-face)))
   ;; (cons 'markdown-match-pandoc-metadata '((1 markdown-comment-face)
   ;;                                         (2 markdown-metadata-value-face)))
   ;; (cons markdown-regex-hr 'markdown-header-face)
   ;; (cons 'markdown-match-comments '((0 markdown-comment-face)))
   (cons 'markdown-match-code '((0 markdown-inline-code-face)))
   ;; (cons markdown-regex-angle-uri 'markdown-link-face)
   ;; (cons markdown-regex-uri 'markdown-link-face)
   ;; (cons markdown-regex-email 'markdown-link-face)
   ;; (cons markdown-regex-list '(2 markdown-list-face))
   ;; (cons markdown-regex-footnote 'markdown-footnote-face)
   ;; (cons markdown-regex-link-inline '((1 markdown-link-face t t)
   ;;                                    (2 markdown-link-face t)
   ;;                                    (4 markdown-url-face t)
   ;;                                    (6 markdown-link-title-face t t)))
   ;; (cons markdown-regex-link-reference '((1 markdown-link-face t t)
   ;;                                       (2 markdown-link-face t)
   ;;                                       (4 markdown-reference-face t)))
   ;; (cons markdown-regex-reference-definition '((1 markdown-reference-face t)
   ;;                                             (2 markdown-url-face t)
   ;;                                             (3 markdown-link-title-face t)))
   ;; (cons markdown-regex-bold '(2 markdown-bold-face))
   ;; (cons markdown-regex-line-break '(1 markdown-line-break-face prepend))
   )
  "Syntax highlighting for Markdown files.")

(defun markdown-match-code (last)
  "Match inline code from the point to LAST."
  (unless (bobp)
    (backward-char 1))
  (cond ((re-search-forward markdown-regex-code last t)
         (set-match-data (list (match-beginning 2) (match-end 2)
                               (match-beginning 4) (match-end 4)))
         (goto-char (match-end 0))
         t)
        (t (forward-char 2) nil)))

(defun markdown-match-fenced-code-blocks (last)
  "Match fenced code blocks from the point to LAST."
  (cond ((search-forward-regexp "^\\([~]\\{3,\\}\\)" last t)
         (beginning-of-line)
         (let ((beg (point)))
           (forward-line)
           (cond ((search-forward-regexp
                   (concat "^" (match-string 1) "~*") last t)
                  (set-match-data (list beg (point)))
                  t)
                 (t nil))))
        (t nil)))

(defun markdown-match-pre-blocks (last)
  ;; (interactive)
  "Match Markdown pre blocks from point to LAST."
  (let ((levels (markdown-calculate-list-levels))
        indent pre-regexp end-regexp begin end stop)
    (while (and (< (point) last) (not end))
      ;; Search for a region with sufficient indentation
      (if (null levels)
          (setq indent 1)
        (setq indent (1+ (length levels))))
      (setq pre-regexp (format "^\\(    \\|\t\\)\\{%d\\}" indent))
      (setq end-regexp (format "^\\(    \\|\t\\)\\{0,%d\\}\\([^ \t]\\)" (1- indent)))

      (cond
       ;; If not at the beginning of a line, move forward
       ((not (bolp)) (forward-line))
       ;; Move past blank lines
       ((markdown-cur-line-blank-p) (forward-line))
       ;; At headers and horizontal rules, reset levels
       ((markdown-new-baseline-p) (forward-line) (setq levels nil))
       ;; If the current line has sufficient indentation, mark out pre block
       ((looking-at pre-regexp)
        (setq begin (match-beginning 0))
        (while (and (or (looking-at pre-regexp) (markdown-cur-line-blank-p))
                    (not (eobp)))
          (forward-line))
        (setq end (point)))
       ;; If current line has a list marker, update levels, move to end of block
       ((looking-at markdown-regex-list)
        (setq levels (markdown-update-list-levels
                      (match-string 2) (markdown-cur-line-indent) levels))
        (markdown-end-of-block-element))
       ;; If this is the end of the indentation level, adjust levels accordingly.
       ;; Only match end of indentation level if levels is not the empty list.
       ((and (car levels) (looking-at end-regexp))
        (setq levels (markdown-update-list-levels
                      nil (markdown-cur-line-indent) levels))
        (markdown-end-of-block-element))
       (t (markdown-end-of-block-element))))

    (if (not (and begin end))
        ;; Return nil if no pre block was found
        nil
      ;; Set match data and return t upon success
      (set-match-data (list begin end))
      t)))

(defun markdown-end-of-block-element ()
  "Move the point to the start of the next block unit.
Stops at blank lines, list items, headers, and horizontal rules."
  (interactive)
  (forward-line)
  (while (and (or (not (markdown-prev-line-blank-p))
                  (markdown-cur-line-blank-p))
              (not (or (looking-at markdown-regex-list)
                       (looking-at markdown-regex-header)
                       ;; (looking-at markdown-regex-hr)
                       ))
              (not (eobp)))
    (forward-line)))

(defun markdown-calculate-list-levels ()
  "Calculate list levels at point.
Return a list of the form (n1 n2 n3 ...) where n1 is the
indentation of the deepest nested list item in the branch of
the list at the point, n2 is the indentation of the parent
list item, and so on.  The depth of the list item is therefore
the length of the returned list.  If the point is not at or
immediately  after a list item, return nil."
  (save-excursion
    (let ((first (point)) levels indent pre-regexp)
      ;; Find a baseline point with zero list indentation
      (markdown-search-backward-baseline)
      ;; Search for all list items between baseline and LOC
      (while (and (< (point) first)
                  (re-search-forward markdown-regex-list first t))
        (setq pre-regexp (format "^\\(    \\|\t\\)\\{%d\\}" (1+ (length levels))))
        (beginning-of-line)
        (cond
         ;; Make sure this is not a header or hr
         ((markdown-new-baseline-p) (setq levels nil))
         ;; Make sure this is not a line from a pre block
         ((looking-at pre-regexp))
         ;; If not, then update levels
         (t
          (setq indent (markdown-cur-line-indent))
          (setq levels (markdown-update-list-levels (match-string 2)
                                                    indent levels))))
        (end-of-line))
      levels)))

(defun markdown-search-backward-baseline ()
  "Search backward baseline point with no indentation and not a list item."
  (end-of-line)
  (let (stop)
    (while (not (or stop (bobp)))
      (re-search-backward markdown-regex-block-separator nil t)
      (when (match-end 2)
        (goto-char (match-end 2))
        (cond
         ((markdown-new-baseline-p)
          (setq stop t))
         ((looking-at markdown-regex-list)
          (setq stop nil))
         (t (setq stop t)))))))

(defun markdown-update-list-levels (marker indent levels)
  "Update list levels given list MARKER, block INDENT, and current LEVELS.
Here, MARKER is a string representing the type of list, INDENT is an integer
giving the indentation, in spaces, of the current block, and LEVELS is a
list of the indentation levels of parent list items.  When LEVELS is nil,
it means we are at baseline (not inside of a nested list)."
  (cond
   ;; New list item at baseline.
   ((and marker (null levels))
    (setq levels (list indent)))
   ;; List item with greater indentation (four or more spaces).
   ;; Increase list level.
   ((and marker (>= indent (+ (car levels) 4)))
    (setq levels (cons indent levels)))
   ;; List item with greater or equal indentation (less than four spaces).
   ;; Do not increase list level.
   ((and marker (>= indent (car levels)))
    levels)
   ;; Lesser indentation level.
   ;; Pop appropriate number of elements off LEVELS list (e.g., lesser
   ;; indentation could move back more than one list level).  Note
   ;; that this block need not be the beginning of list item.
   ((< indent (car levels))
    (while (and (> (length levels) 1)
                (< indent (+ (cadr levels) 4)))
      (setq levels (cdr levels)))
    levels)
   ;; Otherwise, do nothing.
   (t levels)))

(defun markdown-new-baseline-p ()
  "Determine if the current line begins a new baseline level."
  (save-excursion
    (beginning-of-line)
    (save-match-data
      (or (looking-at markdown-regex-header)
          ;; (looking-at markdown-regex-hr)
          (and (null (markdown-cur-non-list-indent))
               (= (markdown-cur-line-indent) 0)
               (markdown-prev-line-blank-p))))))

(defun markdown-cur-non-list-indent ()
  "Return beginning position of list item text (not including the list marker).
Return nil if the current line is not the beginning of a list item."
  (save-match-data
    (save-excursion
      (beginning-of-line)
      (when (re-search-forward markdown-regex-list (line-end-position) t)
        (current-column)))))

(defun markdown-reload-extensions ()
  "Check settings, update font-lock keywords, and re-fontify buffer."
  (interactive)
  (when (eq major-mode 'markdown-lite-mode)
    ;; (setq markdown-mode-font-lock-keywords
    ;;       (append
    ;;        (when markdown-enable-math
    ;;          markdown-mode-font-lock-keywords-math)
    ;;        markdown-mode-font-lock-keywords-basic
    ;;        markdown-mode-font-lock-keywords-core))
    (setq font-lock-defaults '(markdown-mode-font-lock-keywords-basic))
    (font-lock-refresh-defaults)))