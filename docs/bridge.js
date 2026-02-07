window.flutterBridge = {
    elements: {},
    isTrackerLoaded: false,
    virtualScrollY: 0, 

    initTracker: function() {
        if (this.isTrackerLoaded) return;
        
        try {
            const getScroll = () => this.virtualScrollY;
            Object.defineProperty(window, 'scrollY', { get: getScroll, configurable: true });
            Object.defineProperty(window, 'pageYOffset', { get: getScroll, configurable: true });
        } catch (e) {}

        this._ensureHiddenInput('ts1-client-id', '123');
        const baseEl = document.querySelector('base');
        const baseUrl = baseEl ? baseEl.href : (window.location.origin + '/');
        const script = document.createElement('script');
        script.src = baseUrl + 'tracker.js';
        script.async = true;
        document.head.appendChild(script);
        this.isTrackerLoaded = true;
    },

    triggerScroll: function(pixels) {
        this.virtualScrollY = pixels;
        if (document.body.scrollHeight < pixels + window.innerHeight) {
            document.body.style.minHeight = (pixels + window.innerHeight + 200) + 'px';
        }
        window.dispatchEvent(new Event('scroll', { bubbles: true }));
    },

    triggerUrlChange: function(newUrl) {
        this.virtualScrollY = 0;
        window.dispatchEvent(new Event('popstate'));
        window.dispatchEvent(new Event('hashchange'));
    },

    triggerClick: function(id, x, y) {
        const el = this._getOrCreateElement(id, 'div');
        el.style.left = x + 'px'; el.style.top = y + 'px';
        const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
        el.dispatchEvent(new MouseEvent('mousedown', opts));
        el.dispatchEvent(new MouseEvent('mouseup', opts));
        el.dispatchEvent(new MouseEvent('click', opts));
    },

    // ==========================================
    // === ГОЛОВНЕ ВИПРАВЛЕННЯ ДЛЯ ПОЛЯ "a" ===
    // ==========================================
    setFocus: function(id, hasFocus) {
        const el = this._getOrCreateElement(id, 'input');
        
        if (hasFocus) {
            // 1. ЕМУЛЯЦІЯ ФІЗИЧНОГО КЛІКУ (Щоб трекер повірив)
            // Трекери чекають mousedown перед фокусом
            const mouseOpts = { bubbles: true, cancelable: true, view: window };
            el.dispatchEvent(new MouseEvent('mousedown', mouseOpts));
            el.dispatchEvent(new MouseEvent('mouseup', mouseOpts));
            el.dispatchEvent(new MouseEvent('click', mouseOpts));

            // 2. ЕМУЛЯЦІЯ ФОКУСУ
            // focus - не спливає, focusin - спливає (важливо для трекера)
            el.dispatchEvent(new FocusEvent('focus', { bubbles: false, cancelable: true, view: window }));
            el.dispatchEvent(new FocusEvent('focusin', { bubbles: true, cancelable: true, view: window }));
        } else {
            // ДЕАКТИВАЦІЯ
            el.dispatchEvent(new Event('change', { bubbles: true })); 
            el.dispatchEvent(new FocusEvent('blur', { bubbles: false, cancelable: true, view: window }));
            el.dispatchEvent(new FocusEvent('focusout', { bubbles: true, cancelable: true, view: window }));
        }
    },

    typeChar: function(id, text, char, start, end) {
        const el = this._getOrCreateElement(id, 'input');
        el.value = text;
        
        if (typeof start === 'number') {
            try { el.setSelectionRange(start, end); } catch(e){}
        }

        const keyOpts = { 
            key: char, 
            code: `Key${char.toUpperCase()}`, 
            bubbles: true, 
            cancelable: true, 
            view: window 
        };
        
        el.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
        el.dispatchEvent(new KeyboardEvent('keypress', keyOpts));
        el.dispatchEvent(new InputEvent('input', { 
            bubbles: true, 
            inputType: 'insertText',
            data: char,
            view: window
        }));
        el.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
    },

    pressBackspace: function(id, text, start, end) {
        const el = this._getOrCreateElement(id, 'input');
        el.value = text;
        try { el.setSelectionRange(start, end); } catch(e){}

        const bsOpts = { key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8, bubbles: true, cancelable: true, view: window };

        el.dispatchEvent(new KeyboardEvent('keydown', bsOpts));
        el.dispatchEvent(new InputEvent('input', { 
            bubbles: true, 
            inputType: 'deleteContentBackward',
            data: null,
            view: window
        }));
        el.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
    },

    _getOrCreateElement: function(id, type) {
        let el = document.getElementById(id);
        if (el && el.tagName.toLowerCase() !== type) { el.remove(); el = null; }
        if (!el) {
            el = document.createElement(type);
            el.id = id;
            el.setAttribute('data-ts1-id', id); 
            // Використовуємо pointer-events: auto для JS подій, але ховаємо візуально
            el.style.position = 'fixed';
            el.style.opacity = '0.01'; 
            el.style.zIndex = '-1'; 
            el.style.top = '0';
            el.style.left = '0';
            // Важливо: дозволяємо події, але елемент під низом
            el.style.pointerEvents = 'auto'; 
            
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