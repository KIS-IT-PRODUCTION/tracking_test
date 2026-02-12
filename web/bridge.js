window.flutterBridge = {
    elements: {},
    isTrackerLoaded: false,
    virtualScrollY: 0, 

    initTracker: function() {
        if (this.isTrackerLoaded) return;
        
        console.log("[Bridge] Initializing V4 (First-Click Fix)...");
        
        try {
            localStorage.removeItem('tracker_data_pending');
            this._ensureHiddenInput('ts1-client-id', '123');
        } catch (e) {}

        const baseEl = document.querySelector('base');
        let baseUrl = baseEl ? baseEl.href : window.location.href;
        if (baseUrl.includes('index.html')) baseUrl = baseUrl.replace('index.html', '');
        if (!baseUrl.endsWith('/')) baseUrl += '/';
        
        const trackerUrl = baseUrl + 'tracker.js';

        fetch(trackerUrl)
            .then(response => response.text())
            .then(originalCode => {
                let patchedCode = originalCode
                    .replace(/window\.scrollY/g, 'window.flutterBridge.virtualScrollY')
                    .replace(/window\.pageYOffset/g, 'window.flutterBridge.virtualScrollY')
                    .replace(/document\.documentElement\.scrollTop/g, '(window.flutterBridge.virtualScrollY || 0)')
                    .replace(/document\.body\.scrollTop/g, '(window.flutterBridge.virtualScrollY || 0)');

                const blob = new Blob([patchedCode], { type: 'text/javascript' });
                const blobUrl = URL.createObjectURL(blob);
                
                const script = document.createElement('script');
                script.src = blobUrl;
                script.async = true;
                document.head.appendChild(script);
                
                this.isTrackerLoaded = true;
                console.log("[Bridge] Tracker loaded.");
            })
            .catch(err => {
                console.error("[Bridge] Failed to load tracker:", err);
            });
    },

    handleNavigation: function(prev, next) {
        console.log(`[Bridge] Nav: ${prev} -> ${next}`);
        this.virtualScrollY = 0; 
        try { document.dispatchEvent(new Event('locationchange')); } catch(e) {}
    },

    triggerScroll: function(pixels) {
        this.virtualScrollY = pixels;
        window.dispatchEvent(new Event('scroll'));
        document.dispatchEvent(new Event('scroll'));
    },

    typeChar: function(id, text, char, start, end) {
        const el = this._getOrCreateElement(id, 'input');
        
        const charCode = char.charCodeAt(0);
        const keyOpts = {
            key: char,
            code: `Key${char.toUpperCase()}`,
            keyCode: charCode,
            which: charCode,
            bubbles: true,
            cancelable: true,
            view: window
        };

        el.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
        el.dispatchEvent(new KeyboardEvent('keypress', keyOpts));

        el.value = text;
        if (typeof start === 'number') {
            try { el.setSelectionRange(start, end); } catch(e){}
        }

        el.dispatchEvent(new InputEvent('input', {
            bubbles: true,
            cancelable: false,
            inputType: 'insertText',
            data: char,
            view: window
        }));

        el.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
    },

    pressBackspace: function(id, text, start, end) {
        const el = this._getOrCreateElement(id, 'input');
        
        const bsOpts = {
            key: 'Backspace',
            code: 'Backspace',
            keyCode: 8,
            which: 8,
            bubbles: true,
            cancelable: true,
            view: window
        };
        
        el.dispatchEvent(new KeyboardEvent('keydown', bsOpts));
        el.value = text;
        if (typeof start === 'number') { try { el.setSelectionRange(start, end); } catch(e){} }

        el.dispatchEvent(new InputEvent('input', {
            bubbles: true,
            inputType: 'deleteContentBackward',
            data: null,
            view: window
        }));
        
        el.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
    },
    
    // --- ВИПРАВЛЕННЯ ТУТ ---
    setFocus: function(id, hasFocus) {
        const el = this._getOrCreateElement(id, 'input');
        
        if (hasFocus) {
            // setTimeout(..., 10) - це магія.
            // Це дозволяє реальному кліку Flutter завершитись ДО того, як ми запустимо фейковий.
            setTimeout(() => {
                try {
                    const rect = el.getBoundingClientRect();
                    const opts = {
                        bubbles: true, cancelable: true, view: window,
                        clientX: rect.left, clientY: rect.top
                    };
                    
                    // 1. "Розігріваємо" трекер: мишка наїхала -> нажала -> відпустила -> клікнула
                    el.dispatchEvent(new MouseEvent('mouseover', opts)); 
                    el.dispatchEvent(new MouseEvent('mousedown', opts));
                    el.dispatchEvent(new MouseEvent('mouseup', opts));
                    el.dispatchEvent(new MouseEvent('click', opts));
                    
                    // 2. Фокусуємо
                    el.dispatchEvent(new FocusEvent('focus', { bubbles: false, view: window }));
                    el.dispatchEvent(new FocusEvent('focusin', { bubbles: true, view: window }));
                    
                } catch(e) { console.warn(e); }
            }, 10); // Затримка 10мс критично важлива для першого разу
            
        } else {
            // Деактивація
            setTimeout(() => {
                el.dispatchEvent(new Event('change', { bubbles: true })); 
                el.dispatchEvent(new FocusEvent('blur', { bubbles: false, view: window }));
                el.dispatchEvent(new FocusEvent('focusout', { bubbles: true, view: window }));
            }, 0);
        }
    },

    triggerClick: function(id, x, y) {
        try {
            const el = this._getOrCreateElement(id, 'div');
            el.style.left = x + 'px'; 
            el.style.top = y + 'px';
            const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            // Додаємо mouseover і тут, про всяк випадок
            el.dispatchEvent(new MouseEvent('mouseover', opts));
            el.dispatchEvent(new MouseEvent('mousedown', opts));
            el.dispatchEvent(new MouseEvent('mouseup', opts));
            el.dispatchEvent(new MouseEvent('click', opts));
        } catch(e) {}
    },

    // --- ДОПОМІЖНІ ---
    _getOrCreateElement: function(id, type) {
        let el = document.getElementById(id);
        if (el && el.tagName.toLowerCase() !== type) { el.remove(); el = null; }
        
        if (!el) {
            el = document.createElement(type);
            el.id = id;
            el.setAttribute('data-ts1-id', id);
            
            el.style.position = 'fixed';
            el.style.left = '0px';
            el.style.top = '0px';
            el.style.width = '20px'; 
            el.style.height = '20px';
            el.style.opacity = '0.01'; 
            el.style.pointerEvents = 'none'; 
            el.style.zIndex = '-9999';
            el.style.border = 'none';
            el.style.outline = 'none';
            
            if (type === 'input') {
                el.setAttribute('autocomplete', 'off');
            }

            document.body.appendChild(el);
            this.elements[id] = el;
        }
        return el;
    },
    
    _ensureHiddenInput: function(id, value) {
        if (!document.getElementById(id)) {
            const i = document.createElement('input');
            i.id = id; i.type = 'hidden'; i.value = value;
            document.body.appendChild(i);
        }
    }
};


// window.flutterBridge = {
//     elements: {},
//     isTrackerLoaded: false,
//     virtualScrollY: 0, // Зберігаємо тут позицію скролу від Flutter

//     initTracker: function() {
//         if (this.isTrackerLoaded) return;
        
//         console.log("[Bridge] Pre-init setup...");
//         localStorage.removeItem('tracker_data_pending');
//         this._ensureHiddenInput('ts1-client-id', '123');

//         // --- 1. БЕЗПЕЧНИЙ SHIM СКРОЛУ (Без window.scrollY) ---
//         try {
//             const getScroll = () => this.virtualScrollY;
            
//             // Ми НЕ чіпаємо window.scrollY, щоб не вбити Flutter.
//             // Підміняємо тільки властивості документа:
//             Object.defineProperty(document.documentElement, 'scrollTop', { get: getScroll, configurable: true });
//             Object.defineProperty(document.body, 'scrollTop', { get: getScroll, configurable: true });
            
//             console.log("[Bridge] Safe scroll properties ready.");
//         } catch (e) {
//             console.warn("[Bridge] Failed to shim scroll:", e);
//         }

//         // --- 2. ЗАТРИМКА ЗАВАНТАЖЕННЯ (35 секунд) ---
//         console.log("[Bridge] Waiting 35 seconds before loading tracker...");
        
//         setTimeout(() => {
//             console.log("[Bridge] 35 seconds passed. Injecting script now...");
            
//             try {
//                 const baseEl = document.querySelector('base');
//                 let baseUrl = baseEl ? baseEl.href : window.location.href;
//                 if (baseUrl.includes('index.html')) baseUrl = baseUrl.replace('index.html', '');
//                 if (!baseUrl.endsWith('/')) baseUrl += '/';

//                 const script = document.createElement('script');
//                 script.src = baseUrl + 'tracker.js'; 
//                 script.async = true;
//                 document.head.appendChild(script);
                
//                 this.isTrackerLoaded = true;
//                 console.log("[Bridge] Tracker script injected.");
//             } catch (e) { 
//                 console.warn("[Bridge] Error injecting script:", e); 
//             }
//         }, 35000); // <-- ТУТ ЗАТРИМКА (35000 мс = 35 секунд)
//     },

//     handleNavigation: function(prev, next) {
//         console.log(`[Bridge] Nav: ${prev} -> ${next}`);
//         this.virtualScrollY = 0; 
        
//         window.dispatchEvent(new Event('popstate'));
//         window.dispatchEvent(new Event('locationchange')); 
//         window.dispatchEvent(new Event('hashchange'));
//     },

//     // --- КЛІК ---
//     triggerClick: function(id, x, y) {
//         const el = this._getOrCreateElement(id, 'div');
//         el.style.left = x + 'px'; 
//         el.style.top = y + 'px';
//         const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
//         el.dispatchEvent(new MouseEvent('mousedown', opts));
//         el.dispatchEvent(new MouseEvent('mouseup', opts));
//         el.dispatchEvent(new MouseEvent('click', opts));
//     },

//     // --- ВВІД СИМВОЛУ ---
//     typeChar: function(id, text, char, start, end) {
//         const el = this._getOrCreateElement(id, 'input');
//         el.value = text;
        
//         if (typeof start === 'number') {
//             try { el.setSelectionRange(start, end); } catch(e){}
//         }

//         const keyOpts = { key: char, code: `Key${char.toUpperCase()}`, bubbles: true, cancelable: true, view: window };
//         el.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
//         el.dispatchEvent(new KeyboardEvent('keypress', keyOpts));
        
//         el.dispatchEvent(new InputEvent('input', { 
//             bubbles: true, 
//             inputType: 'insertText', 
//             data: char, 
//             view: window 
//         }));
        
//         el.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
//         el.dispatchEvent(new Event('change', { bubbles: true }));
//     },

//     // --- ВИДАЛЕННЯ (Backspace) ---
//     pressBackspace: function(id, text, start, end) {
//         const el = this._getOrCreateElement(id, 'input');
//         el.value = text;
        
//         if (typeof start === 'number') {
//             try { el.setSelectionRange(start, end); } catch(e){}
//         }

//         const bsOpts = { key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8, bubbles: true, cancelable: true, view: window };
        
//         el.dispatchEvent(new KeyboardEvent('keydown', bsOpts));
//         el.dispatchEvent(new InputEvent('input', { 
//             bubbles: true, 
//             inputType: 'deleteContentBackward', 
//             data: null, 
//             view: window 
//         }));
//         el.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
//         el.dispatchEvent(new Event('change', { bubbles: true }));
//     },
    
//     // --- ФОКУС ---
//     setFocus: function(id, hasFocus) {
//         const el = this._getOrCreateElement(id, 'input');
//         if (hasFocus) {
//             el.focus();
//             el.dispatchEvent(new FocusEvent('focus', { bubbles: true }));
//         } else {
//             el.blur();
//             el.dispatchEvent(new FocusEvent('blur', { bubbles: true }));
//         }
//     },

//     // --- СКРОЛ ---
//     triggerScroll: function(pixels) {
//         this.virtualScrollY = pixels;
        
//         try { document.documentElement.scrollTop = pixels; } catch(e) {}

//         window.dispatchEvent(new Event('scroll', { bubbles: true }));
//         document.dispatchEvent(new Event('scroll', { bubbles: true }));
//     },

//     // --- ДОПОМІЖНІ ---
//     _getOrCreateElement: function(id, type) {
//         let el = document.getElementById(id);
//         if (el && el.tagName.toLowerCase() !== type) { el.remove(); el = null; }
//         if (!el) {
//             el = document.createElement(type);
//             el.id = id;
//             el.setAttribute('data-ts1-id', id); 
            
//             // Ghost стилі
//             el.style.position = 'fixed';
//             el.style.width = '1px'; el.style.height = '1px';
//             el.style.opacity = '0.01'; 
//             el.style.zIndex = '-1'; 
//             el.style.pointerEvents = 'none'; 
//             document.body.appendChild(el);
//             this.elements[id] = el;
//         }
//         return el;
//     },
    
//     _ensureHiddenInput: function(id, value) {
//         if (!document.getElementById(id)) {
//             const i = document.createElement('input');
//             i.id = id; i.type = 'hidden'; i.value = value;
//             document.body.appendChild(i);
//         }
//     }
// };