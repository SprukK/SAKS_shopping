import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Link, Route, Routes, useNavigate, useParams } from "react-router-dom";
import {
  supabase,
  configured,
  ensureAuth,
  rememberName,
  savedName,
  tripKey,
} from "./lib";
import type { Audit, Meal, Participant, ShoppingItem, Trip } from "./types";
const cats = {
  food: "Hrana / obroki",
  drinks: "Pijača",
  boat: "Plovilo",
  other: "Drugo",
} as const;
const mealTypes = {
  breakfast: "Zajtrk",
  lunch: "Kosilo",
  dinner: "Večerja",
  other: "Drugo",
} as const;
function ErrorBox({ text }: { text: string }) {
  return <p className="error">{text}</p>;
}
type InstallEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};
function Home() {
  const nav = useNavigate();
  const [trips, setTrips] = useState<Trip[]>([]);
  const [name, setName] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [install, setInstall] = useState<InstallEvent | null>(null);
  const load = useCallback(async () => {
    if (!configured) {
      setLoading(false);
      return;
    }
    try {
      await ensureAuth();
      const { data, error } = await supabase
        .from("trips")
        .select("*")
        .order("start_date", { ascending: false });
      if (error) throw error;
      setTrips(data || []);
    } catch (x) {
      setError(x instanceof Error ? x.message : String(x));
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    load();
    const handler = (event: Event) => {
      event.preventDefault();
      setInstall(event as InstallEvent);
    };
    window.addEventListener("beforeinstallprompt", handler);
    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, [load]);
  async function installApp() {
    if (!install) return;
    await install.prompt();
    await install.userChoice;
    setInstall(null);
  }
  async function create(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (!configured)
        throw new Error("Najprej nastavi Supabase spremenljivke.");
      await ensureAuth();
      const { data, error } = await supabase.rpc("create_trip", {
        p_name: name,
        p_start_date: start,
        p_end_date: end,
        p_display_name: savedName() || "Kapitan",
      });
      if (error) throw error;
      const t = data as Trip;
      nav(`/trip/${t.share_token}`);
    } catch (x) {
      setError(x instanceof Error ? x.message : String(x));
    } finally {
      setBusy(false);
    }
  }
  return (
    <main>
      <header className="hero">
        <span className="sail">⛵</span>
        <h1>SAKS Nakupovanje</h1>
        <p>Obroki in skupni nakupi za plovbo.</p>
        {install && (
          <button className="secondary install" onClick={installApp}>
            Namesti aplikacijo
          </button>
        )}
      </header>
      <section>
        <h2>Plovbe</h2>
        {loading ? (
          <p className="muted">Nalaganje…</p>
        ) : trips.length ? (
          trips.map((t) => (
            <Link className="trip" to={`/trip/${t.share_token}`} key={t.id}>
              <span>
                <strong>{t.name}</strong>
                <small>
                  {t.start_date} – {t.end_date}
                </small>
              </span>
              <span>
                {t.status === "archived" ? "Arhivirana" : "Aktivna"} ›
              </span>
            </Link>
          ))
        ) : (
          <p className="muted">Ni še nobene plovbe. Ustvari prvo spodaj.</p>
        )}
      </section>
      <section className="card">
        <h2>Nova plovba</h2>
        <form onSubmit={create}>
          <label>
            Ime plovbe
            <input
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Hrvaška 2027"
            />
          </label>
          <div className="dates">
            <label>
              Začetek
              <input
                required
                type="date"
                value={start}
                onChange={(e) => setStart(e.target.value)}
              />
            </label>
            <label>
              Konec
              <input
                required
                type="date"
                min={start}
                value={end}
                onChange={(e) => setEnd(e.target.value)}
              />
            </label>
          </div>
          <button disabled={busy}>
            {busy ? "Ustvarjam…" : "Ustvari plovbo"}
          </button>
        </form>
        {error && <ErrorBox text={error} />}
      </section>
    </main>
  );
}
function TripPage() {
  const { token = "" } = useParams();
  const nav = useNavigate();
  const [trip, setTrip] = useState<Trip | null>(null);
  const [me, setMe] = useState<Participant | null>(null);
  const [name, setName] = useState(savedName());
  const [tab, setTab] = useState<"meals" | "shopping" | "people" | "activity">(
    "meals",
  );
  const [shoppingMode, setShoppingMode] = useState(false);
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    try {
      await ensureAuth();
      const { data: t, error: e } = await supabase
        .from("trips")
        .select("*")
        .eq("share_token", token)
        .single();
      if (e) throw e;
      setTrip(t);
      const pid = localStorage.getItem(tripKey(token));
      if (pid) {
        const { data: p } = await supabase
          .from("participants")
          .select("*")
          .eq("id", pid)
          .maybeSingle();
        if (p) setMe(p);
      }
    } catch (x) {
      setError(x instanceof Error ? x.message : String(x));
    }
  }, [token]);
  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    if (!trip) return;
    const channel = supabase
      .channel(`trip:${trip.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", filter: `trip_id=eq.${trip.id}` },
        () => load(),
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [trip?.id, load]);
  async function join(e: FormEvent) {
    e.preventDefault();
    try {
      const { data, error } = await supabase.rpc("join_trip", {
        p_share_token: token,
        p_display_name: name,
      });
      if (error) throw error;
      rememberName(name);
      localStorage.setItem(tripKey(token), (data as Participant).id);
      setMe(data);
      load();
    } catch (x) {
      setError(x instanceof Error ? x.message : String(x));
    }
  }
  if (error)
    return (
      <main>
        <Link to="/">← Domov</Link>
        <ErrorBox text={error} />
      </main>
    );
  if (!trip)
    return (
      <main>
        <p>Nalaganje…</p>
      </main>
    );
  if (!me)
    return (
      <main>
        <header className="hero">
          <span className="sail">⛵</span>
          <h1>Dobrodošli na krovu</h1>
          <p>{trip.name}</p>
        </header>
        <section className="card">
          <form onSubmit={join}>
            <label>
              Kako ti je ime?
              <input
                autoFocus
                required
                minLength={2}
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </label>
            <button>Pridruži se</button>
          </form>
        </section>
      </main>
    );
  return (
    <main className={shoppingMode ? "shopping-mode" : ""}>
      <header className="top">
        <button className="secondary back-button" onClick={() => nav("/")}>
          ← Plovbe
        </button>
        <div>
          <small>
            {trip.start_date} – {trip.end_date}
          </small>
          <h1>{trip.name}</h1>
        </div>
        <button
          className="secondary"
          onClick={() => {
            setShoppingMode(!shoppingMode);
            setTab("shopping");
          }}
        >
          {shoppingMode ? "Zapri Shopping Mode" : "🛒 Shopping Mode"}
        </button>
      </header>
      {trip.status === "archived" && (
        <div className="archive">Plovba je arhivirana in samo za branje.</div>
      )}
      {!shoppingMode && (
        <nav>
          <button
            className={tab === "meals" ? "active" : ""}
            onClick={() => setTab("meals")}
          >
            Obroki
          </button>
          <button
            className={tab === "shopping" ? "active" : ""}
            onClick={() => setTab("shopping")}
          >
            Trgovina
          </button>
          <button
            className={tab === "people" ? "active" : ""}
            onClick={() => setTab("people")}
          >
            Ekipa
          </button>
          {me.is_admin && (
            <button
              className={tab === "activity" ? "active" : ""}
              onClick={() => setTab("activity")}
            >
              Dnevnik
            </button>
          )}
        </nav>
      )}
      {!shoppingMode && tab === "meals" && (
        <Meals trip={trip} me={me} readOnly={trip.status === "archived"} />
      )}{" "}
      {(shoppingMode || tab === "shopping") && (
        <Shopping
          trip={trip}
          me={me}
          readOnly={trip.status === "archived"}
          mode={shoppingMode}
        />
      )}{" "}
      {!shoppingMode && tab === "people" && <People trip={trip} me={me} />}{" "}
      {!shoppingMode && tab === "activity" && me.is_admin && (
        <Activity trip={trip} onArchive={load} onDelete={() => nav("/")} />
      )}
    </main>
  );
}
function Meals({
  trip,
  me,
  readOnly,
}: {
  trip: Trip;
  me: Participant;
  readOnly: boolean;
}) {
  const [items, setItems] = useState<Meal[]>([]);
  const [title, setTitle] = useState("");
  const [date, setDate] = useState(trip.start_date);
  const [type, setType] = useState("dinner");
  const load = useCallback(async () => {
    const { data } = await supabase
      .from("meals")
      .select("*,ingredients:meal_ingredients(*)")
      .eq("trip_id", trip.id)
      .order("date");
    setItems(data || []);
  }, [trip.id]);
  useEffect(() => {
    load();
    const c = supabase
      .channel(`meals:${trip.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", filter: `trip_id=eq.${trip.id}` },
        load,
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(c);
    };
  }, [load, trip.id]);
  async function add(e: FormEvent) {
    e.preventDefault();
    await supabase.from("meals").insert({
      trip_id: trip.id,
      date,
      meal_type: type,
      title,
      created_by: me.id,
    });
    setTitle("");
    load();
  }
  async function ingredient(meal: Meal) {
    const name = prompt("Sestavina");
    if (!name) return;
    const quantity = Number(prompt("Količina", "1"));
    const unit = prompt("Enota (neobvezno)", "");
    await supabase.from("meal_ingredients").insert({
      meal_id: meal.id,
      name,
      quantity: Number.isFinite(quantity) ? quantity : 1,
      unit: unit || null,
      created_by: me.id,
    });
    load();
  }
  async function transfer(meal: Meal) {
    await supabase.rpc("add_meal_ingredients_to_shopping", {
      p_meal_id: meal.id,
      p_participant_id: me.id,
    });
    load();
  }
  return (
    <section>
      <div className="section-title">
        <h2>Načrt obrokov</h2>
      </div>
      {!readOnly && (
        <form className="inline card" onSubmit={add}>
          <input
            required
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Ime obroka"
          />
          <input
            required
            type="date"
            min={trip.start_date}
            max={trip.end_date}
            value={date}
            onChange={(e) => setDate(e.target.value)}
          />
          <select value={type} onChange={(e) => setType(e.target.value)}>
            {Object.entries(mealTypes).map(([v, l]) => (
              <option value={v} key={v}>
                {l}
              </option>
            ))}
          </select>
          <button>Dodaj</button>
        </form>
      )}
      {items.map((m) => (
        <article className="card meal" key={m.id}>
          <small>
            {new Date(m.date + "T12:00:00").toLocaleDateString("sl-SI", {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}{" "}
            · {mealTypes[m.meal_type as keyof typeof mealTypes] || m.meal_type}
          </small>
          <h3>{m.title}</h3>
          <ul>
            {m.ingredients?.map((i) => (
              <li key={i.id}>
                {i.quantity} {i.unit} {i.name}
                {i.added_to_shopping && <span> ✓</span>}
              </li>
            ))}
          </ul>
          {!readOnly && (
            <div className="actions">
              <button className="secondary" onClick={() => ingredient(m)}>
                + Sestavina
              </button>
              <button
                disabled={!m.ingredients?.some((i) => !i.added_to_shopping)}
                onClick={() => transfer(m)}
              >
                {m.ingredients?.some((i) => !i.added_to_shopping)
                  ? "Dodaj v Trgovino"
                  : "Dodano v Trgovino"}
              </button>
            </div>
          )}
        </article>
      ))}
      {!items.length && <p className="muted">Dodajte prvi obrok.</p>}
    </section>
  );
}
function Shopping({
  trip,
  me,
  readOnly,
  mode,
}: {
  trip: Trip;
  me: Participant;
  readOnly: boolean;
  mode: boolean;
}) {
  const [items, setItems] = useState<ShoppingItem[]>([]);
  const [name, setName] = useState("");
  const [qty, setQty] = useState(1);
  const [unit, setUnit] = useState("");
  const [category, setCategory] = useState<keyof typeof cats>("other");
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("all");
  const [openItem, setOpenItem] = useState<string | null>(null);
  const [touchX, setTouchX] = useState(0);
  const load = useCallback(async () => {
    const { data } = await supabase
      .from("shopping_items")
      .select(
        "*,buyer:participants!shopping_items_bought_by_fkey(display_name),meal:meals(title)",
      )
      .eq("trip_id", trip.id)
      .order("status")
      .order("created_at");
    setItems((data || []) as ShoppingItem[]);
  }, [trip.id]);
  useEffect(() => {
    load();
    const c = supabase
      .channel(`shop:${trip.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", filter: `trip_id=eq.${trip.id}` },
        load,
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(c);
    };
  }, [load, trip.id]);
  async function add(e: FormEvent) {
    e.preventDefault();
    await supabase.from("shopping_items").insert({
      trip_id: trip.id,
      name,
      quantity: qty,
      unit: unit || null,
      category,
      created_by: me.id,
    });
    setName("");
    setQty(1);
    setUnit("");
    load();
  }
  async function toggle(i: ShoppingItem) {
    if (readOnly) return;
    const next = i.status === "bought" ? "not_bought" : "bought";
    const { error } = await supabase.rpc("set_item_bought", {
      p_item_id: i.id,
      p_participant_id: me.id,
      p_bought: next === "bought",
      p_expected_version: i.version,
    });
    if (error)
      alert("Artikel je medtem spremenil nekdo drug. Seznam bo osvežen.");
    load();
  }
  async function edit(i: ShoppingItem) {
    const nextName = prompt("Artikel", i.name);
    if (!nextName) return;
    const nextQty = Number(prompt("Količina", String(i.quantity)));
    const nextUnit = prompt("Enota", i.unit || "");
    if (!Number.isFinite(nextQty) || nextQty <= 0) return;
    await supabase
      .from("shopping_items")
      .update({
        name: nextName.trim(),
        quantity: nextQty,
        unit: nextUnit || null,
        version: i.version + 1,
        updated_at: new Date().toISOString(),
      })
      .eq("id", i.id);
    setOpenItem(null);
    load();
  }
  async function duplicate(i: ShoppingItem) {
    await supabase.from("shopping_items").insert({
      trip_id: trip.id,
      name: i.name,
      quantity: i.quantity,
      unit: i.unit,
      category: i.category,
      meal_id: i.meal_id,
      meal_ingredient_id: null,
      created_by: me.id,
    });
    setOpenItem(null);
    load();
  }
  async function remove(i: ShoppingItem) {
    if (!confirm(`Odstranim artikel »${i.name}«?`)) return;
    await supabase.from("shopping_items").delete().eq("id", i.id);
    setOpenItem(null);
    load();
  }
  const shown = useMemo(
    () =>
      items.filter(
        (i) =>
          i.name.toLowerCase().includes(search.toLowerCase()) &&
          (filter === "all" || i.status === filter),
      ),
    [items, search, filter],
  );
  const done = items.filter((i) => i.status === "bought").length;
  return (
    <section>
      <div className="progress">
        <strong>
          {done} / {items.length} kupljeno
        </strong>
        <div>
          <span
            style={{
              width: `${items.length ? (done / items.length) * 100 : 0}%`,
            }}
          />
        </div>
      </div>
      <div className="filters">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Išči…"
        />
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="all">Vse</option>
          <option value="not_bought">Ni kupljeno</option>
          <option value="bought">Kupljeno</option>
        </select>
      </div>
      {!readOnly && !mode && (
        <form className="inline card" onSubmit={add}>
          <input
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Artikel"
          />
          <input
            className="short"
            required
            type="number"
            min="0.01"
            step="any"
            value={qty}
            onChange={(e) => setQty(Number(e.target.value))}
          />
          <input
            className="short"
            value={unit}
            onChange={(e) => setUnit(e.target.value)}
            placeholder="Enota"
          />
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value as keyof typeof cats)}
          >
            {Object.entries(cats).map(([v, l]) => (
              <option value={v} key={v}>
                {l}
              </option>
            ))}
          </select>
          <button>Dodaj</button>
        </form>
      )}
      <div className="list">
        {shown.map((i) =>
          mode ? (
            <button
              disabled={readOnly}
              className={`item ${i.status}`}
              onClick={() => toggle(i)}
              key={i.id}
            >
              <span className="check">{i.status === "bought" ? "✓" : "○"}</span>
              <ItemText item={i} />
            </button>
          ) : (
            <div
              className={`manage-row ${openItem === i.id ? "open" : ""}`}
              key={i.id}
              onTouchStart={(e) => setTouchX(e.touches[0].clientX)}
              onTouchEnd={(e) => {
                const delta = e.changedTouches[0].clientX - touchX;
                if (delta < -45) setOpenItem(i.id);
                if (delta > 45) setOpenItem(null);
              }}
            >
              <div className={`item ${i.status}`}>
                <ItemText item={i} />
                {!readOnly && (
                  <button
                    className="row-menu"
                    aria-label="Možnosti artikla"
                    onClick={() => setOpenItem(openItem === i.id ? null : i.id)}
                  >
                    ⋯
                  </button>
                )}
              </div>
              {!readOnly && (
                <div className="item-actions">
                  <button onClick={() => edit(i)}>Uredi</button>
                  <button onClick={() => duplicate(i)}>Podvoji</button>
                  <button className="danger" onClick={() => remove(i)}>
                    Odstrani
                  </button>
                </div>
              )}
            </div>
          ),
        )}
      </div>
    </section>
  );
}
function ItemText({ item: i }: { item: ShoppingItem }) {
  return (
    <span>
      <strong>{i.name}</strong>
      <small>
        {i.quantity} {i.unit || ""} · {cats[i.category]}
        {i.meal?.title ? ` · ${i.meal.title}` : ""}
      </small>
      {i.buyer?.display_name && <em>Kupil/a: {i.buyer.display_name}</em>}
    </span>
  );
}
function People({ trip, me }: { trip: Trip; me: Participant }) {
  const [people, setPeople] = useState<Participant[]>([]);
  const load = useCallback(() => {
    supabase
      .from("participants")
      .select("*")
      .eq("trip_id", trip.id)
      .order("created_at")
      .then(({ data }) => setPeople(data || []));
  }, [trip.id]);
  useEffect(() => {
    load();
  }, [load]);
  async function rename(person: Participant) {
    const displayName = prompt(
      "Novo prikazno ime",
      person.display_name,
    )?.trim();
    if (!displayName || displayName === person.display_name) return;
    const { error } = await supabase.rpc("update_participant_name", {
      p_participant_id: person.id,
      p_display_name: displayName,
    });
    if (error) {
      alert(`Sprememba imena ni uspela: ${error.message}`);
      return;
    }
    if (person.id === me.id) rememberName(displayName);
    load();
  }
  return (
    <section>
      <h2>Ekipa</h2>
      {people.map((p) => (
        <div className="person" key={p.id}>
          <span>👤</span>
          <strong>{p.display_name}</strong>
          {p.is_admin && <small>Kapitan</small>}
          {(p.id === me.id || me.is_admin) && (
            <button className="secondary person-edit" onClick={() => rename(p)}>
              Uredi ime
            </button>
          )}
        </div>
      ))}
    </section>
  );
}
function Activity({
  trip,
  onArchive,
  onDelete,
}: {
  trip: Trip;
  onArchive: () => void;
  onDelete: () => void;
}) {
  const [log, setLog] = useState<Audit[]>([]);
  const [taps, setTaps] = useState(0);
  const [admin, setAdmin] = useState(false);
  useEffect(() => {
    supabase
      .from("audit_log")
      .select("*")
      .eq("trip_id", trip.id)
      .order("created_at", { ascending: false })
      .limit(200)
      .then(({ data }) => setLog(data || []));
  }, [trip.id]);
  useEffect(() => {
    if (taps >= 10) {
      setAdmin(true);
      setTaps(0);
    }
  }, [taps]);
  async function archive() {
    if (!confirm("Arhiviram plovbo? Urejanje ne bo več mogoče.")) return;
    await supabase.rpc("archive_trip", { p_trip_id: trip.id });
    onArchive();
  }
  async function remove() {
    if (
      !confirm(
        `Trajno izbrišem plovbo »${trip.name}« in vse njene obroke, nakupe ter dnevnik? Tega ni mogoče razveljaviti.`,
      )
    )
      return;
    const { error } = await supabase.rpc("delete_trip", {
      p_trip_id: trip.id,
    });
    if (error) {
      alert(`Brisanje ni uspelo: ${error.message}`);
      return;
    }
    onDelete();
  }
  return (
    <section>
      <h2 onClick={() => setTaps((t) => t + 1)}>Dnevnik aktivnosti</h2>
      {admin && trip.status === "active" && (
        <button className="danger" onClick={archive}>
          Arhiviraj plovbo
        </button>
      )}
      {admin && (
        <button className="danger delete-trip" onClick={remove}>
          Trajno izbriši plovbo
        </button>
      )}
      {log.map((a) => (
        <article className="audit" key={a.id}>
          <time>{new Date(a.created_at).toLocaleString("sl-SI")}</time>
          <strong>{a.participant_name || "Sistem"}</strong>
          <span>{a.action_type.replaceAll("_", " ")}</span>
        </article>
      ))}
    </section>
  );
}
export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/trip/:token" element={<TripPage />} />
      <Route path="*" element={<Home />} />
    </Routes>
  );
}
