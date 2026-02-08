window.flutterBridge = {
    elements: {},
    isTrackerLoaded: false,
    virtualScrollY: 0, 

    // Ініціалізація
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
        
        console.log("[Bridge] Tracker initialized.");
    },

    // ==========================================
    // === ЛОГІКА ВІДПРАВКИ ДАНИХ (НОВЕ) ===
    // ==========================================
    
    // Викликається Flutter-ом при зміні сторінки
    handleNavigation: function(prevPageName, newPageName) {
        console.log(`[Bridge] Navigation: ${prevPageName} -> ${newPageName}`);

        // 1. Якщо ми йдемо з якоїсь сторінки (не перший запуск) -> зберігаємо і відправляємо її дані
        if (prevPageName && prevPageName !== 'null') {
            this._commitAndSend(prevPageName);
        }

        // 2. Повідомляємо трекер про нову URL (для віртуальної навігації)
        this.triggerUrlChange(newPageName);
        
        // 3. Очищаємо старі інпути (опціонально, щоб трекер не плутав поля з різних сторінок)
        // this._clearElements(); 
    },

    _commitAndSend: function(pageName) {
        // КРОК 1: Отримати дані від трекера
        // ВАЖЛИВО: Тут треба викликати реальний метод вашого трекера.
        // Наприклад: const data = window.someTracker.getData();
        // Поки що емулюємо збір даних, ґрунтуючись на тому, що ми ввели
        const data = this._mockCollectData(); 

        if (!data) {
            console.log("[Bridge] No data to send.");
            return;
        }

        console.log(`[Bridge] Saving data for ${pageName} to LocalStorage...`);

        // КРОК 2: Зберегти в LocalStorage (як вимагали)
        const lsKey = 'tracker_data_pending';
        localStorage.setItem(lsKey, JSON.stringify({
            page: pageName,
            timestamp: Date.now(),
            payload: data
        }));

        // КРОК 3: Відправка (емуляція Fetch)
        console.log(`%c[Network] Sending Data for ${pageName}...`, "color: green; font-weight: bold; font-size: 14px;");
        console.log("PAYLOAD:", data);

        // Тут має бути реальний fetch
        // fetch('/api/track', { method: 'POST', body: JSON.stringify(data) }).then(...)
        
        // Після успішної відправки можна очистити LS, але поки залишимо, як буфер
        // localStorage.removeItem(lsKey);
        
        // КРОК 4: Скидання трекера (щоб дані не дублювалися на новій сторінці)
        // window.someTracker.reset(); 
    },

    // Функція-заглушка для збору даних (замініть на реальну логіку трекера)
    _mockCollectData: function() {
        // Просто збираємо ID елементів, з якими взаємодіяли
        const activeIds = Object.keys(this.elements);
        if (activeIds.length === 0) return null;
        
        return {
            event: "page_data_collected",
            inputs_interacted: activeIds,
            // Тут буде реальний JSON від трекера
            fake_telemetry: "mouse_moves_and_clicks_data" 
        };
    },

    // ... (Решта функцій без змін: triggerScroll, triggerClick і т.д.) ...
    
    triggerScroll: function(pixels) {
        this.virtualScrollY = pixels;
        if (document.body.scrollHeight < pixels + window.innerHeight) {
            document.body.style.minHeight = (pixels + window.innerHeight + 200) + 'px';
        }
        window.dispatchEvent(new Event('scroll', { bubbles: true }));
    },

    triggerUrlChange: function(newUrl) {
        this.virtualScrollY = 0;
        // Емулюємо зміну історії
        history.pushState({}, "", newUrl === '/' ? '/' : `/${newUrl}`);
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

    _ensureHiddenInput: function(id, value) {
        if (!document.getElementById(id)) {
            const i = document.createElement('input');
            i.id = id; i.type = 'hidden'; i.value = value;
            document.body.appendChild(i);
        }
    }
};