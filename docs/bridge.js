window.flutterBridge = {
    elements: {},
    isTrackerLoaded: false,
    virtualScrollY: 0, 

    initTracker: function() {
        if (this.isTrackerLoaded) return;
        
        // --- ВИПРАВЛЕННЯ №2: Очистка "сміття" при старті ---
        // Щоб старі дані з минулих тестів не відправлялися одразу при оновленні сторінки
        localStorage.removeItem('tracker_data_pending');
        console.log("[Bridge] LocalStorage cleared for fresh start.");

        try {
            const getScroll = () => this.virtualScrollY;
            Object.defineProperty(window, 'scrollY', { get: getScroll, configurable: true });
            Object.defineProperty(window, 'pageYOffset', { get: getScroll, configurable: true });
        } catch (e) {}

        this._ensureHiddenInput('ts1-client-id', '123');
        const baseEl = document.querySelector('base');
        const baseUrl = baseEl ? baseEl.href : (window.location.origin + '/');
        
        // Додаємо сам скрипт трекера
        const script = document.createElement('script');
        script.src = baseUrl + 'tracker.js'; // Переконайтесь, що файл tracker.js лежить поруч з index.html
        script.async = true;
        document.head.appendChild(script);
        
        this.isTrackerLoaded = true;
        console.log("[Bridge] Tracker initialized.");
    },

    // ==========================================
    // === ГОЛОВНА ЛОГІКА ПЕРЕХОДУ ===
    // ==========================================
    handleNavigation: function(prevPageName, newPageName) {
        console.log(`[Bridge] Navigation: ${prevPageName} -> ${newPageName}`);

        // Якщо це не перший запуск (ми йдемо зі старої сторінки)
        if (prevPageName && prevPageName !== 'null') {
            
            // 1. ПРИМУСОВА ВІДПРАВКА (Fix Issue #4)
            // Ми емулюємо подію visibilitychange, ніби юзер пішов зі сторінки.
            // Більшість трекерів слухають це і відправляють дані МИТТЄВО.
            this._simulateVisibilityChange('hidden');
            
            // 2. Викликаємо нашу логіку збереження (на всяк випадок)
            this._commitAndSend(prevPageName);
        }

        // 3. Змінюємо URL (віртуально)
        this.triggerUrlChange(newPageName);
        
        // 4. "Повертаємо" користувача на сторінку (для нової сесії)
        if (prevPageName && prevPageName !== 'null') {
            setTimeout(() => {
                this._simulateVisibilityChange('visible');
            }, 50);
        }
    },

    _simulateVisibilityChange: function(state) {
        // state = 'visible' або 'hidden'
        Object.defineProperty(document, 'visibilityState', { value: state, writable: true });
        Object.defineProperty(document, 'hidden', { value: state === 'hidden', writable: true });
        document.dispatchEvent(new Event('visibilitychange'));
        console.log(`[Bridge] Emulated visibility change to: ${state}`);
    },

    _commitAndSend: function(pageName) {
        // Тут збираємо дані
        const data = this._mockCollectData(); 
        
        if (!data) return;

        console.log(`%c[Network] FORCED SENDING DATA for ${pageName}...`, "color: red; font-weight: bold; font-size: 16px;");
        
        // --- ВАЖЛИВО ДЛЯ КЛІЄНТА ---
        // Якщо у трекера є метод типу tracker.flush() або tracker.sendNow() - викличте його тут!
        // Наприклад:
        // if (window.someTracker && window.someTracker.flush) {
        //     window.someTracker.flush();
        // }
    },

    _mockCollectData: function() {
        const activeIds = Object.keys(this.elements);
        if (activeIds.length === 0) return null;
        return { event: "page_data", inputs: activeIds };
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
        const cleanUrl = newUrl.startsWith('/') ? newUrl : `/${newUrl}`;
        history.pushState({}, "", cleanUrl);
        
        // Тригеримо події, щоб трекер помітив зміну URL
        window.dispatchEvent(new Event('popstate'));
        window.dispatchEvent(new Event('hashchange'));
        // Деякі трекери слухають locationchange (нестандартна подія, але буває)
        window.dispatchEvent(new Event('locationchange')); 
    },

    triggerClick: function(id, x, y) {
        const el = this._getOrCreateElement(id, 'div');
        el.style.left = x + 'px'; el.style.top = y + 'px';
        const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
        el.dispatchEvent(new MouseEvent('mousedown', opts));
        el.dispatchEvent(new MouseEvent('mouseup', opts));
        el.dispatchEvent(new MouseEvent('click', opts));
    },

    setFocus: function(id, hasFocus) {
        const el = this._getOrCreateElement(id, 'input');
        if (hasFocus) {
            const mouseOpts = { bubbles: true, cancelable: true, view: window };
            el.dispatchEvent(new MouseEvent('mousedown', mouseOpts));
            el.dispatchEvent(new MouseEvent('mouseup', mouseOpts));
            el.dispatchEvent(new MouseEvent('click', mouseOpts));
            el.dispatchEvent(new FocusEvent('focus', { bubbles: false, cancelable: true, view: window }));
            el.dispatchEvent(new FocusEvent('focusin', { bubbles: true, cancelable: true, view: window }));
        } else {
            el.dispatchEvent(new Event('change', { bubbles: true })); 
            el.dispatchEvent(new FocusEvent('blur', { bubbles: false, cancelable: true, view: window }));
            el.dispatchEvent(new FocusEvent('focusout', { bubbles: true, cancelable: true, view: window }));
        }
    },

    typeChar: function(id, text, char, start, end) {
        const el = this._getOrCreateElement(id, 'input');
        el.value = text;
        if (typeof start === 'number') try { el.setSelectionRange(start, end); } catch(e){}
        const keyOpts = { key: char, code: `Key${char.toUpperCase()}`, bubbles: true, cancelable: true, view: window };
        el.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
        el.dispatchEvent(new KeyboardEvent('keypress', keyOpts));
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: char, view: window }));
        el.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
    },

    pressBackspace: function(id, text, start, end) {
        const el = this._getOrCreateElement(id, 'input');
        el.value = text;
        try { el.setSelectionRange(start, end); } catch(e){}
        const bsOpts = { key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8, bubbles: true, cancelable: true, view: window };
        el.dispatchEvent(new KeyboardEvent('keydown', bsOpts));
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentBackward', data: null, view: window }));
        el.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
    },
    
    // Додана функція оновлення значення (для надійності)
    updateInput: function(id, text, isBackspace) {
         const el = this._getOrCreateElement(id, 'input');
         el.value = text;
         el.dispatchEvent(new InputEvent('input', { bubbles: true, view: window }));
    },

    _getOrCreateElement: function(id, type) {
        let el = document.getElementById(id);
        if (el && el.tagName.toLowerCase() !== type) { el.remove(); el = null; }
        if (!el) {
            el = document.createElement(type);
            el.id = id;
            el.setAttribute('data-ts1-id', id); 
            el.style.position = 'fixed';
            el.style.opacity = '0.01'; 
            el.style.zIndex = '-1'; 
            el.style.top = '0';
            el.style.left = '0';
            el.style.pointerEvents = 'auto'; 
            document.body.appendChild(el);
            this.elements[id] = el;
        }
        return el;
    },
    
    registerElement: function(id) {
        // Просто створюємо елемент наперед
        this._getOrCreateElement(id, 'div');
    },

    _ensureHiddenInput: function(id, value) {
        if (!document.getElementById(id)) {
            const i = document.createElement('input');
            i.id = id; i.type = 'hidden'; i.value = value;
            document.body.appendChild(i);
        }
    }
};