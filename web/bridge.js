window.flutterBridge = {
    elements: {},
    isTrackerLoaded: false,
    // Змінна, де ми зберігаємо позицію скролу, яку передав Flutter
    virtualScrollY: 0, 

    initTracker: function() {
        if (this.isTrackerLoaded) return;
        
        console.log("[Bridge] Initializing & Hijacking Scroll...");

        // --- МАГІЯ: ПЕРЕХОПЛЕННЯ СКРОЛУ ---
        // Ми підміняємо стандартні властивості браузера.
        // Коли tracker.js запитає window.scrollY, він отримає наше значення.
        try {
            const getScroll = () => this.virtualScrollY;

            Object.defineProperty(window, 'scrollY', { get: getScroll, configurable: true });
            Object.defineProperty(window, 'pageYOffset', { get: getScroll, configurable: true });
            
            // Деякі старі трекери шукають тут:
            Object.defineProperty(document.documentElement, 'scrollTop', { get: getScroll, configurable: true, set: (v) => {} });
            Object.defineProperty(document.body, 'scrollTop', { get: getScroll, configurable: true, set: (v) => {} });
        } catch (e) {
            console.warn("[Bridge] Scroll hijacking warning:", e);
        }

        // --- СТАНДАРТНИЙ СТАРТ ---
        this._ensureHiddenInput('ts1-client-id', '123'); // ВАШ ID КЛІЄНТА
        
        const script = document.createElement('script');
        // Використовуємо абсолютний шлях, щоб уникнути помилок 404
        script.src = window.location.origin + '/tracker.js';
        script.async = true;
        document.head.appendChild(script);
        
        this.isTrackerLoaded = true;
    },

    // --- ОТРИМАННЯ СКРОЛУ ВІД FLUTTER ---
    triggerScroll: function(pixels) {
        // 1. Зберігаємо реальні пікселі від Flutter у віртуальну змінну
        this.virtualScrollY = pixels;
        
        // 2. Емулюємо висоту сторінки (щоб трекер міг порахувати % прокрутки)
        // Якщо Flutter каже, що ми прокрутили на 5000px, а body має висоту 0, трекер збожеволіє.
        if (document.body.scrollHeight < pixels + window.innerHeight) {
            document.body.style.minHeight = (pixels + window.innerHeight + 200) + 'px';
        }

        // 3. Кричимо браузеру, що скрол відбувся
        window.dispatchEvent(new Event('scroll', { bubbles: true }));
        document.dispatchEvent(new Event('scroll', { bubbles: true }));
    },

    // --- ЗМІНА URL (sU) ---
    triggerUrlChange: function(newUrl) {
        // При переході на нову сторінку скидаємо скрол
        this.virtualScrollY = 0;
        console.log("[Bridge] Virtual Navigation to:", newUrl);
        
        // Емулюємо події навігації
        window.dispatchEvent(new Event('popstate'));
        window.dispatchEvent(new Event('hashchange'));
    },

    // --- КЛІКИ ---
    triggerClick: function(id, x, y) {
        const el = this._getOrCreateElement(id, 'div');
        // Телепортуємо елемент під курсор
        el.style.left = x + 'px'; 
        el.style.top = y + 'px';

        const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, screenX: x, screenY: y };
        el.dispatchEvent(new MouseEvent('mousedown', opts));
        el.dispatchEvent(new MouseEvent('mouseup', opts));
        el.dispatchEvent(new MouseEvent('click', opts));
    },

    // --- ВВІД ТЕКСТУ ---
    updateInput: function(id, text, isBackspace) {
        const el = this._getOrCreateElement(id, 'input');
        el.value = text;
        el.dispatchEvent(new InputEvent('input', { 
            bubbles: true, 
            inputType: isBackspace ? 'deleteContentBackward' : 'insertText',
            data: text 
        }));
    },
    
    setFocus: function(id, hasFocus) {
         const el = this._getOrCreateElement(id, 'input');
         if(hasFocus) el.focus(); else el.blur();
    },

    // --- ДОПОМІЖНІ ФУНКЦІЇ ---
    registerElement: function(id) { this._getOrCreateElement(id, 'div'); },

    _getOrCreateElement: function(id, type) {
        let el = document.getElementById(id);
        if (el && el.tagName.toLowerCase() !== type) { el.remove(); el = null; }
        if (!el) {
            el = document.createElement(type);
            el.id = id;
            el.style.position = 'fixed'; 
            el.style.zIndex = '99999'; 
            el.style.opacity = '0.01'; 
            el.style.pointerEvents = 'none';
            el.style.width = '10px'; 
            el.style.height = '10px';
            el.setAttribute('data-ts1-id', id); 
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