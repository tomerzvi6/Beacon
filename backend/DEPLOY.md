# פריסת ה-Backend לאינטרנט (Fly.io)

הכל מוכן — Dockerfile, fly.toml, ‎.dockerignore. נשארו הצעדים שדורשים חשבון שלך (~20 דק').

## צעדים חד-פעמיים

```bash
# 1. התקנת CLI והרשמה (חינם, צריך כרטיס אשראי לאימות)
brew install flyctl
fly auth signup            # או fly auth login

cd backend

# 2. יצירת האפליקציה (בלי לדרוס את fly.toml הקיים)
fly launch --no-deploy --copy-config
# אם השם beacon-parser-api תפוס — בחר שם אחר, ועדכן אותו
# גם ב-fly.toml (app + LOCAL_API_BASE_URL)

# 3. דאטהבייס Postgres מנוהל
fly postgres create --name beacon-db --region fra
fly postgres attach beacon-db
# הפקודה מזריקה DATABASE_URL אוטומטית. חשוב: הקוד משתמש בדרייבר
# psycopg3 — ודא שה-URL בפורמט postgresql+psycopg:// :
fly secrets set DATABASE_URL="postgresql+psycopg://<user>:<pass>@beacon-db.flycast:5432/beacon_parser_api"
# (את הערך המלא מקבלים מ-fly postgres attach / fly ssh console -a beacon-db)

# 4. נפח אחסון למסמכים שמועלים
fly volumes create beacon_uploads --region fra --size 3

# 5. סודות
fly secrets set \
  ANTHROPIC_API_KEY="sk-ant-..." \
  JWT_SIGNING_KEY="$(openssl rand -hex 32)"

# 6. דיפלוי
fly deploy

# 7. בדיקה
curl https://beacon-parser-api.fly.dev/health   # או כל route קיים
```

## חיבור האפליקציה

ב-`Beacon/Secrets.plist` לעדכן:

```
BACKEND_URL = https://beacon-parser-api.fly.dev
```

ולבנות מחדש. זהו — מכשירים אמיתיים מעלים מסמכים מכל מקום.

## הערות

- **עלות**: מכונה shared-1x + Postgres קטן + נפח ‎3GB ≈ ‎5-10$ לחודש. עם `min_machines_running = 0` המכונה נרדמת כשאין תנועה (בקשה ראשונה אחרי שינה איטית ב-2-3 שניות).
- **JWT_SIGNING_KEY**: חייב להיות קבוע — החלפה שלו מנתקת את כל המשתמשים.
- **גיבויים**: Fly Postgres כולל snapshots יומיים. לפני פיילוט אמיתי שקול Neon/Supabase-DB עם גיבויים חזקים יותר.
- **ENVIRONMENT=production** כבר מוגדר ב-fly.toml — זה מפעיל את בדיקות האבטחה (JWT key חובה, nonce של Google נאכף).
- אלטרנטיבה: Railway (railway.app) — אותו Dockerfile עובד שם as-is; מגדירים את אותם משתני סביבה ב-UI.
