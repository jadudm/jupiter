#lang racket

(provide plumb%)

(require racket/gui
         net/url
         net/dns
         net/base64
         json)

(require "arduino-interaction.rkt"
         "util.rkt"
         "mvc.rkt"
         "seq.rkt"
         "debug.rkt"
         "util.rkt"
         "response-handling.rkt"
         "code-execution.rkt"
         "config-client.rkt"
         )

(define MIN-FIRMWARE-SIZE 10000)

(define plumb%
  (class model%
    (super-new)
    (inherit update add-view)
    
    ;   ;;;;;;; ;;  ;;;;;;;  ;;      ;;;;;;       ;;   
    ;   ;;;;;;; ;;  ;;;;;;;  ;;      ;;;;;;;    ;;;;;  
    ;   ;;      ;;  ;;       ;;      ;;    ;;   ;; ;   
    ;   ;;      ;;  ;;       ;;      ;;     ;;  ;;     
    ;   ;;;;;;  ;;  ;;;;;;   ;;      ;;      ;  ;;;    
    ;   ;;;;;;  ;;  ;;;;;;   ;;      ;;      ;    ;;;  
    ;   ;;      ;;  ;;       ;;      ;;      ;      ;; 
    ;   ;;      ;;  ;;       ;;      ;;     ;;      ;; 
    ;   ;;      ;;  ;;       ;;      ;;    ;;   ;   ;; 
    ;   ;;      ;;  ;;       ;;;;;;; ;;;;;;;    ;; ;;; 
    ;   ;;      ;;  ;;;;;;;  ;;;;;;; ;;;;;;      ;;;;  
    
    (field [host false]
           [port false]
           [id false]
           
           [config false]
           [board-config false]
           
           [arduino-ports empty]
           [arduino-port false]
           [board-type false]
           
           [main-file false]
           [temp-dir false]
           [firmware-location false]
           
           [compilation-result false]
           [message "Parallel programming for makers."]
           
           [first-compilation? true]
           )
    
    
    ;     ;;    ;;;;;;;    ;;      ;;    ;;     ;;;;     ;;      ;;    ;;   
    ;   ;;;;;   ;;;;;;;  ;;;;;   ;;;;;   ;;   ;;;;;;;;   ;;;     ;;  ;;;;;  
    ;   ;; ;    ;;       ;; ;    ;; ;    ;;  ;;;    ;;;  ;;;;    ;;  ;; ;   
    ;   ;;      ;;       ;;      ;;      ;;  ;;      ;;  ;;;;;   ;;  ;;     
    ;   ;;;     ;;;;;;   ;;;     ;;;     ;;  ;        ;  ;; ;;   ;;  ;;;    
    ;     ;;;   ;;;;;;     ;;;     ;;;   ;;  ;        ;  ;;  ;;  ;;    ;;;  
    ;       ;;  ;;           ;;      ;;  ;;  ;        ;  ;;   ;; ;;      ;; 
    ;       ;;  ;;           ;;      ;;  ;;  ;;      ;;  ;;   ;;;;;      ;; 
    ;   ;   ;;  ;;       ;   ;;  ;   ;;  ;;  ;;;    ;;   ;;    ;;;;  ;   ;; 
    ;   ;; ;;;  ;;       ;; ;;;  ;; ;;;  ;;   ;;;;;;;;   ;;     ;;;  ;; ;;; 
    ;    ;;;;   ;;;;;;;   ;;;;    ;;;;   ;;     ;;;;     ;;      ;;   ;;;;  
    
    (define/public (get-id) id)
    
    (define (get-new-session-id)
      ;; Create a new process object
      (define p (new process% [context 'SESSION-START]))
      
      ;; Define a sequence of operations
      (seq p
        ;; We should be in the initial state, and flag a generic error
        ;; in the event of problems.
        [(initial? 'ERROR)
         (debug 'START-SESSION "DEFAULT ERROR: ~a" (send p to-string))
         (debug 'START-SESSION "SERVER URL: ~a" 
                (url->string
                 (make-server-url host port "start-session")))
         ;; Nothing should change as a result of this operation
         NO-CHANGE]
        
        ;; We should still be in the initial state, and should
        ;; flag a bad connection if all goes wrong.
        [(initial? 'ERROR-NO-CONNECTION)
         (get-pure-port (make-server-url host port "start-session"))]
        
        ;; Now we should have a port, and flag a bad response if 
        ;; things go pear shaped.
        [(port? 'ERROR-PROCESS-RESPONSE)
         (debug 'START-SESSION "PORT: ~a" (send p to-string))
         (process-response (send p get))]
        
        ;; The response should give us a hash table; we'll pull
        ;; out the session ID.
        [(hash? 'ERROR-BAD-RESPONSE)
         (debug 'START-SESSION "RESPONSE: ~a" (send p to-string))
         (hash-ref (send p get) 'sessionid)]
        
        ;; The session ID should be a symbol. We're just displaying
        ;; it as a debug here, so this step should yield no changes.
        [(string? 'ERROR-SESSION-ID-NOT-A-STRING)
         (debug 'START-SESSION "SESSION ID: ~a" (send p get))
         NO-CHANGE])
      
      ;; Set the id according to what we retrieved
      (set! id (send p get))
      )
    
    (define/public (set-remote-host h p)
      (set! host (dns-get-address 
                  (dns-find-nameserver)
                  h))
      (set! port (string->number p))
      (update))
    
    
    ;   ;;;;;;     ;;;;     ;;;;;   ;;;;;;;;    ;;   
    ;   ;;  ;;;  ;;;;;;;;   ;;;;;;; ;;;;;;;;  ;;;;;  
    ;   ;;   ;; ;;;    ;;;  ;;   ;;    ;;     ;; ;   
    ;   ;;   ;; ;;      ;;  ;;   ;;    ;;     ;;     
    ;   ;;   ;; ;        ;  ;;   ;;    ;;     ;;;    
    ;   ;;;;;;; ;        ;  ;;;;;;     ;;       ;;;  
    ;   ;;;;;;  ;        ;  ;;;;;;     ;;         ;; 
    ;   ;;      ;;      ;;  ;;  ;;     ;;         ;; 
    ;   ;;      ;;;    ;;   ;;   ;;    ;;     ;   ;; 
    ;   ;;       ;;;;;;;;   ;;    ;;   ;;     ;; ;;; 
    ;   ;;         ;;;;     ;;    ;;;  ;;      ;;;;  
    
    (define/public (enumerate-arduinos)
      (set! arduino-ports (map ->string (list-arduinos)))
      (update))
    
    (define/public (get-arduino-ports) arduino-ports)
    
    (define (port->platform-specific-port sp)
      (case (system-type)
        [(macosx unix) (format "/dev/~a" sp)]
        [(windows) sp]))
    
    (define/public (set-arduino-port p) 
      (set! arduino-port (port->platform-specific-port p)))
    
    
    ;   ;;;;;;      ;;;;        ;;     ;;;;;    ;;;;;;    
    ;   ;;  ;;    ;;;;;;;;      ;;     ;;;;;;;  ;;;;;;;   
    ;   ;;  ;;;  ;;;    ;;;    ;;;;    ;;   ;;  ;;    ;;  
    ;   ;;  ;;;  ;;      ;;    ;;;;    ;;   ;;  ;;     ;; 
    ;   ;;  ;;   ;        ;    ;  ;;   ;;   ;;  ;;      ; 
    ;   ;;;;;;;  ;        ;   ;;  ;;   ;;;;;;   ;;      ; 
    ;   ;;   ;;; ;        ;   ;;   ;   ;;;;;;   ;;      ; 
    ;   ;;   ;;; ;;      ;;  ;;;;;;;;  ;;  ;;   ;;     ;; 
    ;   ;;   ;;; ;;;    ;;   ;;;;;;;;  ;;   ;;  ;;    ;;  
    ;   ;;;;;;;   ;;;;;;;;   ;;     ;; ;;    ;; ;;;;;;;   
    ;   ;;;;;;      ;;;;    ;;      ;; ;;    ;;;;;;;;;    
    
    (define (board-choice->board-type choice)
      (case choice
        [("Arduino Duemilanove") "arduino"]
        [else "arduino"]))
    
    (define/public (set-board-type b)
      (set! board-type (board-choice->board-type b)))
    
    (define/public (get-board-type) board-type)
    
    (define (get-board-config)
      (define gbc (new process% [context 'RETRIEVE-BOARD-CONFIG]))
      (define firm (new process% [context 'RETRIEVE-BOARD-FIRMWARE]))
      
      (seq gbc
        ;; Create the URL
        [(initial? 'ERROR-GENERATING-URL)
         (make-server-url host port "board" board-type)]
        ;; Get a port
        [(url? 'ERROR-CREATING-PORT)
         (get-pure-port (send gbc get))]
        ;; Parse the response
        [(port? 'ERROR-PARSING-RESPONSE)
         (process-response (send gbc get))]
        ;; Store it
        [(hash? 'ERROR-STORING-BOARD-CONFIG)
         (debug (send gbc get-context) "~a" (filter-hash (send gbc get) 'hex))
         (set! board-config (send gbc get))
         NO-CHANGE])
      
      (seq firm
        ;; Create URL
        [(initial? 'ERROR-GENERATING-URL)
         (make-server-url host port "firmware" (hash-ref board-config 'firmware))]
        ;; Get a port
        [(url? 'ERROR-CREATING-PORT)
         (get-pure-port (send firm get))]
        ;; Parse the response
        [(port? 'ERROR-PARSING-RESPONSE)
         (process-response (send firm get))]
        ;; Check that it came down
        [(hash? 'ERROR-FIRMWARE-LOOKS-KINDA-SHORT)
         (let ([firm-leng (string-length (hash-ref (send firm get) 'hex))])
           (cond
             [(< firm-leng MIN-FIRMWARE-SIZE)
              (raise)]
             [else
              (debug (send firm get-context) "Firmware length: ~a" firm-leng)])
           NO-CHANGE)])
      )
    
    
    ;   ;;;;;;; ;;  ;;      ;;;;;;;    ;;   
    ;   ;;;;;;; ;;  ;;      ;;;;;;;  ;;;;;  
    ;   ;;      ;;  ;;      ;;       ;; ;   
    ;   ;;      ;;  ;;      ;;       ;;     
    ;   ;;;;;;  ;;  ;;      ;;;;;;   ;;;    
    ;   ;;;;;;  ;;  ;;      ;;;;;;     ;;;  
    ;   ;;      ;;  ;;      ;;           ;; 
    ;   ;;      ;;  ;;      ;;           ;; 
    ;   ;;      ;;  ;;      ;;       ;   ;; 
    ;   ;;      ;;  ;;;;;;; ;;       ;; ;;; 
    ;   ;;      ;;  ;;;;;;; ;;;;;;;   ;;;;  
    
    (define/public (set-main-file f)
      (set! main-file f)
      (update))
    
    (define/public (main-file-set?)
      (and main-file (file-exists? main-file)))
    
    (define (create-temp-dir)
      (set! temp-dir
            (case (->sym (system-type))
              [(macosx) 
               (build-path (find-system-path 'temp-dir) id)]
              [(win windows)
               (let ([result (make-parameter false)])
                 (for ([p (map getenv '("TMP" "TEMP" "USERPROFILsE"))])
                   (debug 'CREATE-TEMP-DIR "Exists? [~a]" p)
                   (when (and p
                              (directory-exists? p)
                              (not (result)))
                     (result (build-path p id))))
                 (debug 'CREATE-TEMP-DIR "Using [~a]" (result))
                 (result))]))
      (cond
        [(directory-exists? temp-dir)
         (debug 'CREATE-TEMP-DIR "Temp dir [~a] exists" temp-dir)]
        [else 
         (debug 'CREATE-TEMP-DIR "Creating [~a]" temp-dir)
         (make-directory temp-dir)]))
    
    (define (cleanup-temp-dir)
      (define extensions '(hex))
      (when (directory-exists? temp-dir)
        (for ([f (directory-list temp-dir)])
          (debug 'TEMP-DIR "Checking [~a] for removal." f)
          (when (member (->sym (file-extension f)) extensions)
            (debug 'TEMP-DIR "Removing [~a]." f)
            (delete-file (build-path temp-dir f))))
        (debug 'TEMP-DIR "Removing temp directory [~a]" temp-dir)
        (delete-directory temp-dir)
        (set! temp-dir false)))
    
    
    ;   ;;       ;;    ;;        ;;;;;    ;;   
    ;   ;;;     ;;;  ;;;;;     ;;;  ;;; ;;;;;  
    ;   ;;;;   ;;;;  ;; ;      ;      ; ;; ;   
    ;   ;; ;; ;; ;;  ;;       ;         ;;     
    ;   ;; ;; ;; ;;  ;;;      ;         ;;;    
    ;   ;;  ;;;  ;;    ;;;    ;    ;;;;   ;;;  
    ;   ;;   ;   ;;      ;;   ;      ;;     ;; 
    ;   ;;       ;;      ;;   ;      ;;     ;; 
    ;   ;;       ;;  ;   ;;   ;;     ;; ;   ;; 
    ;   ;;       ;;  ;; ;;;    ;;;;;;;; ;; ;;; 
    ;   ;;       ;;   ;;;;      ;;;;;;   ;;;;  
    
    
    (define/public (get-message) message)
    
    (define/public (get-compilation-result) compilation-result)
    
    
    ;                   ;;   ;;;     ;;;;      ;; ;;;;;;;;     ;;     ;;     ;;;
    ;                 ;;;;;   ;;    ;; ;;;     ;; ;;;;;;;;     ;;      ;;   ;;  
    ;                 ;; ;     ;;  ;;  ;;;;    ;;    ;;       ;;;;      ;;  ;;  
    ;                 ;;        ;;;;   ;;;;;   ;;    ;;       ;;;;      ;;;;;   
    ;          ;      ;;;        ;;;   ;; ;;   ;;    ;;       ;  ;;      ;;;    
    ;          ;        ;;;      ;;    ;;  ;;  ;;    ;;      ;;  ;;      ;;;    
    ;          ;          ;;     ;;    ;;   ;; ;;    ;;      ;;   ;      ;;;;   
    ;          ;          ;;     ;;    ;;   ;;;;;    ;;     ;;;;;;;;    ;; ;;   
    ;         ;       ;   ;;     ;;    ;;    ;;;;    ;;     ;;;;;;;;   ;;   ;;  
    ;         ;       ;; ;;;     ;;    ;;     ;;;    ;;     ;;     ;; ;;     ;; 
    ;         ;        ;;;;      ;;    ;;      ;;    ;;    ;;      ;;;;;      ;;
    ;    ;    ;                                                                 
    ;   ; ;  ;                                                                  
    ;      ; ;                                                                  
    ;       ;;                                                                  
    ;       ;;                                                                  
    ;        ;                                                                  
    
    (define (any? v) v)
    
    
    ;; FIXME
    ;; Need better checks down below
    
    (define/public (check-syntax)
      'FIXME)
    
    
    ;   ;;;;;;; ;;  ;;;;;    ;;       ;; ;;     ;     ;;    ;;     ;;;;;    ;;;;;;; 
    ;   ;;;;;;; ;;  ;;;;;;;  ;;;     ;;;  ;    ;;;    ;     ;;     ;;;;;;;  ;;;;;;; 
    ;   ;;      ;;  ;;   ;;  ;;;;   ;;;;  ;;   ;;;   ;;    ;;;;    ;;   ;;  ;;      
    ;   ;;      ;;  ;;   ;;  ;; ;; ;; ;;  ;;   ;;;   ;;    ;;;;    ;;   ;;  ;;      
    ;   ;;;;;;  ;;  ;;   ;;  ;; ;; ;; ;;   ;  ;; ;;  ;     ;  ;;   ;;   ;;  ;;;;;;  
    ;   ;;;;;;  ;;  ;;;;;;   ;;  ;;;  ;;   ;; ;; ;; ;;    ;;  ;;   ;;;;;;   ;;;;;;  
    ;   ;;      ;;  ;;;;;;   ;;   ;   ;;   ;; ;; ;; ;;    ;;   ;   ;;;;;;   ;;      
    ;   ;;      ;;  ;;  ;;   ;;       ;;   ;;;;   ;;;    ;;;;;;;;  ;;  ;;   ;;      
    ;   ;;      ;;  ;;   ;;  ;;       ;;    ;;;   ;;;    ;;;;;;;;  ;;   ;;  ;;      
    ;   ;;      ;;  ;;    ;; ;;       ;;    ;;;   ;;;    ;;     ;; ;;    ;; ;;      
    ;   ;;      ;;  ;;    ;;;;;       ;;    ;;     ;;   ;;      ;; ;;    ;;;;;;;;;; 
    
    (define (write-firmware)
      (define p (new process% 
                     [context 'WRITE-FIRMWARE]
                     [update (λ (msg)
                               (set! message (format "~a: ~a"
                                                     (send p get-context)
                                                     (->string msg)))
                               (update))]))
      (define FIRM (make-parameter "tvm.hex")) 
      (seq p
        ;; Get the firmware on first compilation
        [(initial? 'ERROR-RETRIEVING-FIRMWARE)
         (get-board-config)
         board-config]
        
        ;; Create a temp directory
        [(any? 'ERROR-CREATE-TEMP-DIRECTORY)
         (debug (send p get-context) "Creating temporary directory")
         (create-temp-dir)
         temp-dir]
        
        ;; Remove old firmware
        [(any? 'ERROR-REMOVE-OLD-FIRMWARE)
         (FIRM (build-path temp-dir (FIRM)))
         
         (debug (send p get-context)
                "Stale firmware at [~a]?"
                (FIRM))
         
         (when (file-exists? (FIRM))
           (debug (send p get-context) "Removing old firmware.")
           (delete-file (FIRM)))
         NO-CHANGE]
        
        ;; Write new firmware
        [(any? 'ERROR-WRITE-FIRMWARE)
         (debug (send p get-context) "Writing firmware to disk.")
         (with-output-to-file (FIRM)
           (thunk 
            (printf "~a~n" (hash-ref board-config 'hex))))
         (debug (send p get-context) "Written.")
         (set! firmware-location (FIRM))
         (file-size (FIRM))]
        
        [(number? 'ERROR-FIRMWARE-SIZE)
         (debug (send p get-context) "Checking filesize.")
         (when (< (send p get) MIN-FIRMWARE-SIZE)
           (set! firmware-location false)
           (set! message (format "TVM Too Small: ~a" (send p get))))
         NO-CHANGE]
        ))
    
    (define (upload-firmware)
      (define p (new process% 
                     [context 'UPLOAD-FIRMWARE]
                     [update (λ (msg)
                               (set! message (format "~a: ~a"
                                                     (send p get-context)
                                                     (->string msg)))
                               (update))]))
      (seq p
        [(initial? 'ERROR-UPLOADING-FIRMWARE)
         (debug (send p get-context) "Uploading firmware.")
         (let ([cmd (avrdude-cmd config firmware-location board-config arduino-port)])
           (debug (send p get-context) "CMD:~n\t~a" cmd)
           (exe-in-tempdir temp-dir cmd)
           )]
        
        [(zero? 'ERROR-WITH-AVRDUDE)
         (debug (send p get-context) "Upload successful.")
         NO-CHANGE]
        ))
    
    
    ;      ;;;;       ;;;;     ;;       ;;  ;;;;;;  ;;  ;;      ;;;;;;; 
    ;    ;;;;;;;;   ;;;;;;;;   ;;;     ;;;  ;;  ;;; ;;  ;;      ;;;;;;; 
    ;   ;;;     ;  ;;;    ;;;  ;;;;   ;;;;  ;;   ;; ;;  ;;      ;;      
    ;   ;;         ;;      ;;  ;; ;; ;; ;;  ;;   ;; ;;  ;;      ;;      
    ;  ;;          ;        ;  ;; ;; ;; ;;  ;;   ;; ;;  ;;      ;;;;;;  
    ;  ;;          ;        ;  ;;  ;;;  ;;  ;;;;;;; ;;  ;;      ;;;;;;  
    ;  ;;          ;        ;  ;;   ;   ;;  ;;;;;;  ;;  ;;      ;;      
    ;  ;;          ;;      ;;  ;;       ;;  ;;      ;;  ;;      ;;      
    ;   ;;      ;  ;;;    ;;   ;;       ;;  ;;      ;;  ;;      ;;      
    ;    ;;;  ;;;   ;;;;;;;;   ;;       ;;  ;;      ;;  ;;;;;;; ;;      
    ;     ;;;;;;      ;;;;     ;;       ;;  ;;      ;;  ;;;;;;; ;;;;;;; 
    
    (define (add-file file-path)
      (define p (new process%  
                     [context 'CHECK-SYNTAX]
                     [update (λ (msg)
                               (set! message (format "~a: ~a"
                                                     (send p get-context)
                                                     (->string msg)))
                               (update))]))
      (seq p
        ;; Check file exists
        [(initial? 'ERROR-NO-FILE)
         (unless (file-exists? file-path) (error))
         NO-CHANGE]
        
        ;; Read the file
        [(initial? 'ERROR-CANNOT-READ)
         (file->string file-path)]
        
        [(string? 'ERROR-PREPARE-JSON)
         (let ([json `((filename . ,(extract-filename file-path))
                       (code . ,(send p get))
                       (sessionid . ,id)
                       (action . "add-file"))])
           (debug 'ADD-FILE "~a" json)
           (make-hash json))]
        
        ;; Encode the jsexpr
        [(hash? 'ERROR-JSON-ENCODE)
         (jsexpr->string (send p get))]
        
        ;; Base64 encode the JSON string
        [(string? 'ERROR-B64-ENCODE)
         (base64-encode (string->bytes/utf-8 (send p get)))]
        
        ;; Do the GET
        [(bytes? 'ERROR-HTTP-GET)
         (get-pure-port
          (make-server-url host port "add-file" (send p get)))]
        
        ;; Process the result
        [(port? 'ERROR-PROCESS-RESPONSE)
         (process-response (send p get))]
        
        ))
    
    
    (define (compile-main-file)
      (define p (new process% 
                     [context 'COMPILE-MAIN-FILE]
                     [update (λ (msg)
                               (set! message (format "~a: ~a"
                                                     (send p get-context)
                                                     (->string msg)))
                               (update))]))
      (debug 'COMPILE "Compiling on HOST ~a PORT ~a~n" host port)
      
      (seq p 
        [(initial? 'ERROR-MAKE-URL)
         (make-server-url host port "compile" id board-type (extract-filename main-file))]
        
        [(url? 'ERROR-MAKE-PORT)
         (get-pure-port (send p get))]
        
        [(port? 'ERROR-PROCESS-RESPONSE)
         (let ([resp (process-response (send p get))])
           (close-input-port (send p get))
           resp)]
        
        [(any? 'ERROR-CHECK-RESPONSE)
         (let ([v (send p get)])
           (cond 
             [(or (error-response? v)
                  (eof-object? v))
              v]
             [else
              (debug 'COMPILE "Code Size: ~a" (string-length
                                               (hash-ref v 'hex)))
              (hash-ref v 'hex)]))])
      (send p get))
    
    
    (define (write-and-upload-code hex)
      (define CODE (make-parameter false))
      (define p (new process% 
                     [context 'WRITE-CODE]
                     [update (λ (msg)
                               (set! message (format "~a: ~a"
                                                     (send p get-context)
                                                     (->string msg)))
                               (update))]))
      (seq p
        [(initial? 'ERROR-RETRIEVING-BOARD-CONFIG)
         (get-board-config)
         board-config]
        
        [(hash? 'ERROR-CREATE-TEMP-DIRECTORY)
         (debug (send p get-context) "Creating temporary directory")
         (create-temp-dir)
         (CODE (build-path temp-dir "code.hex"))
         (CODE)]
        
        [(path? 'ERROR-WRITE-CODE)
         (debug (send p get-context) "Trying to write code to [~a]" (CODE))
         (parameterize ([current-directory temp-dir])
           (debug (send p get-context) "Checking if file exists to delete.")
           (when (file-exists? (CODE))
             (debug (send p get-context) "Deleting old code.")
             (delete-file (CODE)))
           (debug (send p get-context) "Attempting to write code to temp directory.")
           (with-output-to-file (CODE)
             (thunk
              (printf "~a" hex))))]
        
        [(any? 'ERROR-UPLOAD-CODE)
         (debug (send p get-context) "Attempting to upload code with AVRDUDE.")
         ;; This must be run within the temp directory.
         ;; AVRDUDE on Windows has issues with a full path to the HEX file.
         (let ([cmd (avrdude-cmd config (CODE) board-config arduino-port)])
           (debug (send p get-context) "CMD:~n~a~n" cmd)
           (exe-in-tempdir temp-dir cmd))]
        
        [(any? 'ERROR-UPLOAD-RESULT)
         (cond
           [(zero? (send p get)) 'OK]
           [else (send p get)])])
      
      (send p get)
      )
    
    
    (define/public (compile)
      (define FIXME (λ args true))
      (define p (new process% 
                     [context 'COMPILE]
                     [update (λ (msg)
                               (set! message (format "~a: ~a"
                                                     (send p get-context)
                                                     (->string msg)))
                               (update))]))
      (seq p
        ;; Get a session ID
        [(initial? 'ERROR-ID-FETCH)
         (get-new-session-id)
         id]
        ;; Check
        [(string? 'DEBUG)
         (set! message (format "Session ID: ~a" id))
         (update)
         NO-CHANGE]
        
        ;; Load system configuration
        [(string? 'ERROR-LOADING-SYSTEM-CONFIGURATION)
         (set! config (new client-config%))
         NO-CHANGE]
        
        ;; Write out the firmware
        [(FIXME 'ERROR-WRITING-FIRMWARE)
         (when first-compilation?
           (write-firmware)
           (upload-firmware)
           (set! first-compilation? false))
         NO-CHANGE]
        
        ;; List the files in the code directory
        [(pass 'ERROR-LISTING-FILES)
         (parameterize ([current-directory (extract-filedir main-file)])
           (filter (λ (f)
                     (member (->sym (file-extension f))
                             '(occ inc module)))
                   (filter file-exists? (directory-list))))]
        
        ;; Add them to the server
        [(list? 'ERROR-ADDING-FILES)
         (debug 'COMPILE "Adding files: ~a" (send p get))
         (send p message "Uploading code.")
         (parameterize ([current-directory (extract-filedir main-file)])
           (for ([f (send p get)])
             (add-file f)))
         NO-CHANGE]
        
        ;; Tell the server to compile
        [(list? 'ERROR-COMPILING-CODE)
         (send p message "Compiling code.")
         (compile-main-file)]
        
        [(string? 'ERROR-WRITING-CODE)
         (send p message "Sending code to Arduino.")
         (write-and-upload-code (send p get))]
        
        [(symbol? 'DEBUG)
         (let ([positives '("Everything's groovy."
                            "Five-by-five on the Arduino."
                            "Super-freaky code is running on the Arduino."
                            "I'm running AMAZING code."
                            "You should be well chuffed."
                            "Good job."
                            "One giant program for Arduino kind."
                            "Help, I'm stuck in an Arduino factory!")])
         (case (send p get)
           [(OK) (send p message (list-ref positives (random (length positives))))]
           [else
            (send p message (format "GURU MEDITATION NUMBER ~a"
                                    (number->string (+ (random 2000000) 2000000) 16)))])
           )]
        
        ))
    
    ))