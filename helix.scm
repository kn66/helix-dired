(require "helix/static.scm")
(require "helix/editor.scm")
(require "helix/misc.scm")
(require (prefix-in keymaps. "helix/keymaps.scm"))
(require (prefix-in helix. "helix/commands.scm"))
(require "steel/result")
(require-builtin steel/filesystem)
(require-builtin steel/process)

(provide DIRED
         DIRED-KEYBINDINGS
         dired-install-keybindings
         dired
         dired-current-directory
         dired-refresh
         dired-open
         dired-toggle
         dired-mark
         dired-unmark
         dired-unmark-all
         dired-create-file
         dired-create-directory
         dired-copy
         dired-move
         dired-paste
         dired-rename
         dired-delete)

(define DIRED "helix-dired")

(define DIRED-KEYBINDINGS
  (hash "normal"
        (hash "ret" ':dired-open
              "tab" ':dired-toggle
              "g" ':dired-refresh
              "m" ':dired-mark
              "u" ':dired-unmark
              "U" ':dired-unmark-all
              "n" (hash "f" ':dired-create-file
                        "d" ':dired-create-directory)
              "y" ':dired-copy
              "x" ':dired-move
              "p" ':dired-paste
              "r" ':dired-rename
              "D" ':dired-delete)))

(define *dired-root* #false)
(define *dired-expanded* '())
(define *dired-marked* '())
(define *dired-line-paths* '())
(define *dired-clipboard-op* #false)
(define *dired-clipboard-paths* '())
(define *dired-buffer-path* "/tmp/helix-dired")
(define *dired-command-stdout* "/tmp/helix-dired.stdout")
(define *dired-command-stderr* "/tmp/helix-dired.stderr")
(define *dired-keybindings-installed?* #false)

;;@doc
;; Install helix-dired keybindings for the generated dired buffer.
(define (dired-install-keybindings)
  (unless *dired-keybindings-installed?*
    (let ([base (keymaps.deep-copy-global-keybindings)])
      (keymaps.merge-keybindings base DIRED-KEYBINDINGS)
      (keymaps.set-global-buffer-or-extension-keymap (hash DIRED base))
      (set! *dired-keybindings-installed?* #true)
      "installed helix-dired keybindings")))

(define (path-join . parts)
  (cond
    [(null? parts) ""]
    [(null? (cdr parts)) (car parts)]
    [else
     (let ([left (trim-end-matches (car parts) "/")]
           [right (trim-start-matches (apply path-join (cdr parts)) "/")])
       (cond
         [(equal? left "") right]
         [(equal? left "/") (string-append "/" right)]
         [else (string-append left "/" right)]))]))

(define (absolute-path? path)
  (starts-with? path "/"))

(define (resolve-path base value)
  (if (absolute-path? value)
      value
      (path-join base value)))

(define (current-file-path)
  (with-handler
    (lambda (_) #false)
    (cx->current-file)))

(define (current-directory-path)
  (let ([file (current-file-path)])
    (cond
      [(and file (is-dir? file)) file]
      [(and file (is-file? file)) (parent-name file)]
      [else (get-helix-cwd)])))

(define (path-member? path paths)
  (cond
    [(null? paths) #false]
    [(equal? path (car paths)) #true]
    [else (path-member? path (cdr paths))]))

(define (remove-path path paths)
  (cond
    [(null? paths) '()]
    [(equal? path (car paths)) (remove-path path (cdr paths))]
    [else (cons (car paths) (remove-path path (cdr paths)))]))

(define (toggle-list-path path paths)
  (if (path-member? path paths)
      (remove-path path paths)
      (cons path paths)))

(define (entry-path entry) (list-ref entry 0))
(define (entry-dir? entry) (list-ref entry 1))
(define (entry-depth entry) (list-ref entry 2))

(define (directory-children root depth)
  (map (lambda (path) (list path (is-dir? path) depth))
       (read-dir root)))

(define (build-entries root depth)
  (let loop ([entries (directory-children root depth)]
             [acc '()])
    (cond
      [(null? entries) (reverse acc)]
      [else
       (let* ([entry (car entries)]
              [path (entry-path entry)]
              [next-acc (cons entry acc)])
         (if (and (entry-dir? entry) (path-member? path *dired-expanded*))
             (loop (cdr entries)
                   (append (reverse (build-entries path (+ depth 1))) next-acc))
             (loop (cdr entries) next-acc)))])))

(define (repeat-string value count)
  (if (<= count 0)
      ""
      (string-append value (repeat-string value (- count 1)))))

(define (entry-line entry)
  (let* ([path (entry-path entry)]
         [dir? (entry-dir? entry)]
         [depth (entry-depth entry)]
         [mark (if (path-member? path *dired-marked*) "*" " ")]
         [tree (cond
                 [(not dir?) "  "]
                 [(path-member? path *dired-expanded*) "- "]
                 [else "+ "])]
         [suffix (if dir? "/" "")]
         [indent (repeat-string "  " depth)])
    (string-append mark " " indent tree (file-name path) suffix)))

(define (render-lines entries)
  (append
    (list (string-append "helix-dired: " *dired-root*)
          "RET open/toggle  m mark  u unmark  n f file  n d dir  y copy  x move  p paste  r rename  D delete  g refresh"
          "")
    (map entry-line entries)))

(define (line-map entries)
  (append (list #false #false #false)
          (map entry-path entries)))

(define (write-lines path lines)
  (let ([port (open-output-file path #:exists 'truncate)])
    (display (string-join lines "\n") port)
    (display "\n" port)
    (close-port port)))

(define (render-dired!)
  (let* ([entries (build-entries *dired-root* 0)]
         [lines (render-lines entries)])
    (set! *dired-line-paths* (line-map entries))
    (write-lines *dired-buffer-path* lines)))

(define (open-dired-buffer!)
  (helix.open *dired-buffer-path*)
  (with-handler
    (lambda (_) #false)
    (let* ([focus (editor-focus)]
           [doc-id (editor->doc-id focus)])
      (set-scratch-buffer-name! DIRED)
      (keymaps.*reverse-buffer-map-insert* (doc-id->usize doc-id) DIRED))))

;;@doc
;; Open a Dired-like file manager rooted at PATH or the current directory.
(define (dired [path #false])
  (let ([root (if path path (current-directory-path))])
    (unless (path-exists? root)
      (error (string-append "dired root does not exist: " root)))
    (unless (is-dir? root)
      (error (string-append "dired root is not a directory: " root)))
    (dired-install-keybindings)
    (set! *dired-root* root)
    (set! *dired-expanded* '())
    (set! *dired-marked* '())
    (render-dired!)
    (open-dired-buffer!)
    (set-status! (string-append "dired: " root))))

;;@doc
;; Open dired at the current buffer's directory.
(define (dired-current-directory)
  (dired (current-directory-path)))

(define (current-dired-path)
  (let ([line (get-current-line-number)])
    (if (< line (length *dired-line-paths*))
        (list-ref *dired-line-paths* line)
        #false)))

(define (selected-paths)
  (let ([current (current-dired-path)])
    (cond
      [(not (null? *dired-marked*)) (reverse *dired-marked*)]
      [current (list current)]
      [else '()])))

(define (target-directory)
  (let ([path (current-dired-path)])
    (cond
      [(and path (is-dir? path)) path]
      [(and path (is-file? path)) (parent-name path)]
      [else *dired-root*])))

;;@doc
;; Refresh the dired buffer from disk.
(define (dired-refresh)
  (if *dired-root*
      (begin
        (render-dired!)
        (open-dired-buffer!)
        (set-status! "dired refreshed"))
      (set-error! "dired is not open")))

;;@doc
;; Toggle directory expansion at the current line.
(define (dired-toggle)
  (let ([path (current-dired-path)])
    (cond
      [(not path) (set-error! "no dired entry on this line")]
      [(not (is-dir? path)) (set-error! "current dired entry is not a directory")]
      [else
       (set! *dired-expanded* (toggle-list-path path *dired-expanded*))
       (dired-refresh)])))

;;@doc
;; Open the current file, or toggle the current directory.
(define (dired-open)
  (let ([path (current-dired-path)])
    (cond
      [(not path) (set-error! "no dired entry on this line")]
      [(is-dir? path) (dired-toggle)]
      [else (helix.open path)])))

;;@doc
;; Mark the current entry for a later multi-file operation.
(define (dired-mark)
  (let ([path (current-dired-path)])
    (if path
        (begin
          (unless (path-member? path *dired-marked*)
            (set! *dired-marked* (cons path *dired-marked*)))
          (dired-refresh))
        (set-error! "no dired entry on this line"))))

;;@doc
;; Unmark the current entry.
(define (dired-unmark)
  (let ([path (current-dired-path)])
    (if path
        (begin
          (set! *dired-marked* (remove-path path *dired-marked*))
          (dired-refresh))
        (set-error! "no dired entry on this line"))))

;;@doc
;; Clear all dired marks.
(define (dired-unmark-all)
  (set! *dired-marked* '())
  (dired-refresh))

(define (touch-file! path)
  (when (path-exists? path)
    (error (string-append "file already exists: " path)))
  (let ([port (open-output-file path)])
    (close-port port)))

;;@doc
;; Prompt for a new file path relative to the current target directory.
(define (dired-create-file)
  (let ([base (target-directory)])
    (push-component!
      (prompt "New file: "
              (lambda (input)
                (let ([path (resolve-path base (trim input))])
                  (touch-file! path)
                  (dired-refresh)
                  (set-status! (string-append "created file " path))))))))

;;@doc
;; Prompt for a new directory path relative to the current target directory.
(define (dired-create-directory)
  (let ([base (target-directory)])
    (push-component!
      (prompt "New directory: "
              (lambda (input)
                (let ([path (resolve-path base (trim input))])
                  (when (path-exists? path)
                    (error (string-append "path already exists: " path)))
                  (create-directory! path)
                  (dired-refresh)
                  (set-status! (string-append "created directory " path))))))))

(define (run-command program args)
  (let ([builder (command program args)])
    (with-stdout builder (open-output-file *dired-command-stdout* #:exists 'truncate))
    (with-stderr builder (open-output-file *dired-command-stderr* #:exists 'truncate))
    (let* ([child (unwrap-ok (spawn-process builder))]
           [status (unwrap-ok (wait child))])
      (if (equal? status 0)
          status
          (error (string-append program " failed with status " (to-string status)))))))

(define (set-clipboard! op paths)
  (if (null? paths)
      (set-error! "no dired entries selected")
      (begin
        (set! *dired-clipboard-op* op)
        (set! *dired-clipboard-paths* paths)
        (set-status!
          (string-append "dired " op " staged "
                         (to-string (length paths))
                         " path(s)")))))

;;@doc
;; Stage marked entries, or the current entry, for copy.
(define (dired-copy)
  (set-clipboard! "copy" (selected-paths)))

;;@doc
;; Stage marked entries, or the current entry, for move.
(define (dired-move)
  (set-clipboard! "move" (selected-paths)))

(define (copy-one! source destination)
  (run-command "cp" (list "-R" source destination)))

(define (move-one! source destination)
  (run-command "mv" (list source destination)))

;;@doc
;; Paste staged copy/move entries into the current target directory.
(define (dired-paste)
  (cond
    [(not *dired-clipboard-op*) (set-error! "dired clipboard is empty")]
    [(null? *dired-clipboard-paths*) (set-error! "dired clipboard is empty")]
    [else
     (let ([dest (target-directory)])
       (for-each
         (lambda (path)
           (if (equal? *dired-clipboard-op* "copy")
               (copy-one! path dest)
               (move-one! path dest)))
         *dired-clipboard-paths*)
       (when (equal? *dired-clipboard-op* "move")
         (set! *dired-clipboard-op* #false)
         (set! *dired-clipboard-paths* '()))
       (set! *dired-marked* '())
       (dired-refresh)
       (set-status! (string-append "pasted into " dest)))]))

(define (rename-target old input)
  (let ([value (trim input)])
    (if (absolute-path? value)
        value
        (path-join (parent-name old) value))))

;;@doc
;; Rename the current entry. Relative input is resolved beside the entry.
(define (dired-rename)
  (let ([path (current-dired-path)])
    (if path
        (push-component!
          (prompt "Rename to: "
                  (lambda (input)
                    (let ([dest (rename-target path input)])
                      (run-command "mv" (list path dest))
                      (set! *dired-marked* (remove-path path *dired-marked*))
                      (dired-refresh)
                      (set-status! (string-append "renamed to " dest))))))
        (set-error! "no dired entry on this line"))))

(define (dangerous-delete-path? path)
  (or (equal? path "/")
      (equal? path *dired-root*)))

(define (delete-path! path)
  (when (dangerous-delete-path? path)
    (error (string-append "refusing to delete protected path: " path)))
  (run-command "rm" (list "-rf" path)))

;;@doc
;; Delete marked entries, or the current entry, after confirmation.
(define (dired-delete)
  (let ([paths (selected-paths)])
    (if (null? paths)
        (set-error! "no dired entries selected")
        (push-component!
          (prompt (string-append "Delete "
                                 (to-string (length paths))
                                 " path(s)? type yes: ")
                  (lambda (input)
                    (if (equal? (string-downcase (trim input)) "yes")
                        (begin
                          (for-each delete-path! paths)
                          (set! *dired-marked* '())
                          (dired-refresh)
                          (set-status! "dired delete complete"))
                        (set-status! "dired delete canceled"))))))))
