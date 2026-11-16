# Regole per scrivere il JSON di una dieta

Queste regole servono a creare un file che l'app accetta al primo colpo, nel formato `germoglio-diet-v1`. Puoi passarle a ChatGPT insieme al piano della nutrizionista (vedi il **§ 14**) oppure seguirle a mano. L'esempio completo e già verificato è in [esempio-dieta.json](esempio-dieta.json).

---

## 1. Come si importa nell'app

1. Apri **Piani** e premi **Importa piano JSON**.
2. Incolla tutto il JSON e premi **Controlla e rivedi**.
3. Se manca qualcosa, l'app mostra l'errore e non salva nulla. Se il JSON è corretto, si apre la schermata di revisione: controlla e premi **Salva**.

All'importazione e al salvataggio l'app rifiuta il JSON se:
- l'`id` è già usato da un'altra dieta;
- le date si **sovrappongono** a una dieta già presente. In quel caso accorcia prima la dieta vecchia oppure scegli date libere.

---

## 2. Struttura generale

Il file è **un solo oggetto JSON**. Usa soltanto questi campi: qualsiasi altro campo, anche scritto male (per esempio `Calories` o `meal`), blocca l'importazione.

```json
{
  "format": "germoglio-diet-v1",
  "id": "dieta-gennaio-2027",
  "name": "Dieta gennaio 2027",
  "from": "2027-01-04",
  "to": "2027-01-31",
  "calories": 1800,
  "mealCalories": {
    "colazione": 400,
    "spuntino_mattina": 150,
    "pranzo": 550,
    "spuntino_pomeriggio": 150,
    "cena": 550
  },
  "color": "#3469A2",
  "meals": {
    "colazione": [],
    "spuntino_mattina": [],
    "pranzo": [],
    "spuntino_pomeriggio": [],
    "cena": []
  },
  "routine": {
    "waterTarget": 2.5,
    "waterNote": "",
    "freeLimit": 1,
    "activities": []
  }
}
```

| Campo | Obbligatorio | Regola esatta |
|---|---|---|
| `format` | sì | Sempre il testo `"germoglio-diet-v1"`. |
| `id` | sì | Solo lettere minuscole, numeri e trattini, al massimo 70 caratteri, niente spazi né accenti. Deve essere nuovo. Es. `dieta-gennaio-2027`. |
| `name` | sì | Il nome che vedi nell'app, al massimo 500 caratteri. |
| `from` / `to` | sì | Formato `AAAA-MM-GG`. `from` non può venire dopo `to`. Entrambe le date sono comprese. |
| `calories` | consigliato | Target giornaliero in kcal: **numero intero**, senza virgolette né decimali. `null` se sconosciuto. |
| `mealCalories` | consigliato | Target di ciascun pasto. Le chiavi sono le stesse di `meals`; ogni valore è un intero oppure `null`. |
| `color` | no | Colore nel formato `#RRGGBB`. Se lo ometti, l'app ne sceglie uno libero. |
| `meals` | sì | Contiene **sempre** le cinque chiavi del § 3, scritte esattamente così. |
| `routine` | no | Acqua, pasti liberi e attività (§ 10). |

---

## 3. I cinque pasti

Le chiavi di `meals` sono esattamente:

| Chiave | Pasto nell'app |
|---|---|
| `colazione` | Colazione |
| `spuntino_mattina` | Spuntino mattina |
| `pranzo` | Pranzo |
| `spuntino_pomeriggio` | Spuntino pomeriggio |
| `cena` | Cena |

Ogni pasto è una **lista di gruppi** (§ 4). I gruppi dello stesso pasto **si sommano**: per esempio a pranzo si sceglie un Piatto, poi le Verdure, e si aggiunge il Condimento. Una lista vuota `[]` è accettata, ma usala solo se quel pasto nel piano davvero non c'è.

---

## 4. Gruppi

Un gruppo è una scelta da fare dentro il pasto.

```json
{ "name": "Verdure", "type": "OR", "options": [ ... ] }
```

| Campo | Regola |
|---|---|
| `name` | Nome del gruppo. Usa i nomi standard della tabella sotto. |
| `type` | `"OR"`, `"AND"` oppure `"MULTI"`, in maiuscolo. |
| `options` | Lista di opzioni (§ 5), **mai vuota**. |
| `min` | Solo con `MULTI`: numero minimo di opzioni da scegliere (intero, da 0 al numero di opzioni). |
| `totalGrams` | Solo con `MULTI`: grammi totali da distribuire tra le opzioni (vedi l'avvertenza nel § 7). |

**Quale `type` usare:**
- **`OR`**: si sceglie **una sola** opzione, per esempio un piatto tra tre o una verdura tra quattro. È il tipo da usare quasi sempre. Usalo anche quando c'è una sola opzione che va comunque toccata.
- **`AND`**: tutte le opzioni vanno prese insieme, per esempio olio + sale o un integratore fisso. Nell'app si spunta ogni voce.
- **`MULTI`**: se ne scelgono più di una, almeno `min`. Usalo solo per voci senza calorie oppure davvero cumulabili (§ 7).

**Nomi standard dei gruppi** (usa sempre questi):

| Nome gruppo | Dove | Tipo |
|---|---|---|
| `Colazione` | colazione | OR |
| `Spuntino` | spuntini | OR |
| `Piatto` | pranzo e cena | OR |
| `Carboidrato` | dentro un piatto a scelta | OR |
| `Carne bianca`, `Carne rossa`, `Pesce`, `Uova`, `Legumi`, `Formaggio`, `Salumi`, `Proteine vegetali`, `Latticini` | dentro un piatto a scelta: lo stesso nome della proteina del piatto | OR |
| `Verdure` | pranzo e cena | OR |
| `Frutta` | dove previsto | OR |
| `Pane` | se il pane è a parte rispetto al piatto | OR |
| `Condimento` | olio e grassi da aggiungere | AND se la quantità è sempre la stessa; OR se cambia secondo il piatto (vedi sotto) |
| `Integratori` | integratori fissi | AND |

**Condimento che cambia secondo il piatto.** Se il piano dà quantità di olio diverse per piatti diversi (per esempio 15 g con il merluzzo, 10 g con il pollo, niente con il salmone), `Condimento` diventa un gruppo **OR** con un'opzione per ogni quantità:
- nome: `Olio EVO 15 g`, `Olio EVO 10 g`… più `Senza olio` con `"calories": 0` se serve;
- in `quantity` si scrivono i piatti a cui si riferisce, per esempio `"15 g · con merluzzo o nasello"`.

---

## 5. Opzioni

Un'opzione è un alimento o un piatto.

```json
{ "name": "Merluzzo", "quantity": "150 g", "icon": "🐟", "calories": 107 }
```

| Campo | Regola |
|---|---|
| `name` | Obbligatorio. Nome dell'alimento o del piatto (§ 6). |
| `quantity` | Testo con l'unità di misura (§ 8). Si omette nei piatti a scelta. |
| `icon` | Una sola emoji (§ 9). Non usare i caratteri `< > " ' &`. |
| `calories` | Intero ≥ 0 oppure `null` (§ 7). |
| `groups` | Solo nei **piatti a scelta**: le sotto-scelte che compaiono quando si tocca il piatto. |
| `weeklyLimit` | Intero > 0: quante volte a settimana si può scegliere quella voce (§ 11). |
| `needsConfirmation` | `true` solo se il piano è ambiguo e la voce va chiarita prima di poterla usare (§ 11). |

Nessun altro campo è ammesso: niente `grams`, `kcal`, `note` o `category`.

---

## 6. Nomi dei piatti: «Carboidrato + Proteina»

Questa è la regola principale per **pranzo e cena**, e anche per colazione e spuntini quando c'è un carboidrato insieme a una proteina.

### 6.1 Formato del nome

```
<Carboidrato> + <Proteina>
```

- Il **carboidrato va sempre per primo** e la **proteina per seconda**.
- Il separatore è esattamente `spazio + spazio` → ` + `.
- Ogni parte inizia con la maiuscola; il resto va in minuscolo, tranne i nomi propri.
- Il nome non contiene grammi, numeri, emoji né la parola «con».
- Verdure, olio, frutta e pane a parte **non entrano nel nome**: vanno nei loro gruppi.

### 6.2 Due tipi di piatto

**Tipo A — piatto a scelta** (il caso normale a pranzo e cena): il piano lascia scegliere il pesce, la carne, ecc.
- Il nome usa la **categoria** della proteina, come `Pasta + Pesce` o `Riso + Carne bianca`.
- Il piatto **non ha** `calories` né `quantity`.
- Dentro `groups` ci sono **esattamente due gruppi `OR`**, in quest'ordine:
  1. `Carboidrato`, con il carboidrato specifico: grammi e calorie.
  2. un gruppo che si chiama **come la categoria della proteina** (`Pesce`, `Carne bianca`…), con gli alimenti specifici: grammi e calorie.

```json
{
  "name": "Pasta + Pesce",
  "icon": "🐟",
  "groups": [
    { "name": "Carboidrato", "type": "OR", "options": [
      { "name": "Pasta integrale", "quantity": "80 g (peso crudo)", "icon": "🍝", "calories": 272 }
    ]},
    { "name": "Pesce", "type": "OR", "options": [
      { "name": "Merluzzo", "quantity": "150 g", "icon": "🐟", "calories": 107 },
      { "name": "Gamberi",  "quantity": "150 g", "icon": "🦐", "calories": 107 }
    ]}
  ]
}
```

**Tipo B — piatto fisso**: tutto è già deciso, senza alternative interne. Succede spesso a colazione e negli spuntini.
- Il nome usa gli **alimenti specifici**, come `Fette biscottate + Ricotta` o `Gallette + Bresaola`.
- Non ha `groups`.
- `quantity` elenca le quantità **nello stesso ordine del nome**, separate da ` + `, per esempio `"30 g + 100 g"`.
- Se il piatto ha **più di due componenti** (per esempio un porridge), nel nome restano solo carboidrato e proteina principali. `quantity` elenca invece **tutti** i componenti, ognuno con quantità e nome: `"Porridge: 60 g avena + 250 ml latte di mandorla + 100 g banana + 20 g whey"`. Può iniziare con il nome comune del piatto seguito da due punti (`Porridge:`, `Pancake:`), così si riconosce subito.
- `calories` è la **somma** delle calorie dei componenti.

```json
{ "name": "Fette biscottate + Ricotta", "quantity": "30 g + 100 g", "icon": "🍞", "calories": 216 }
```

### 6.3 Nomi ammessi

**Carboidrato** (prima parte), da scegliere tra: `Pasta`, `Riso`, `Pane`, `Patate`, `Farro`, `Orzo`, `Couscous`, `Quinoa`, `Gnocchi`, `Piadina`, `Gallette`, `Fette biscottate`, `Avena`, `Cereali`.
- Nel nome del piatto non si scrive la variante: «Pasta integrale», «Riso basmati» e «Pane di segale» diventano semplicemente `Pasta`, `Riso` e `Pane`. La variante va nell'opzione dentro il gruppo `Carboidrato`.
- Se il piano permette due carboidrati con la **stessa quantità** (per esempio «80 g di pasta o riso»), il nome diventa `Pasta o Riso + Pesce` e il gruppo `Carboidrato` contiene entrambe le opzioni.
- Lo stesso vale quando il piano dichiara un carboidrato **sostituto** dell'altro anche con quantità diverse (per esempio «al posto di 130 g di pasta puoi usare 110 g di riso + 30 g di pane»): il nome è `Pasta o Riso + Pesce` e il sostituto è un'opzione fissa del gruppo `Carboidrato` (`Riso integrale + Pane`, `"110 g + 30 g"`). Un eventuale limite («max 3–4 volte a settimana») si scrive nella sua `quantity`.
- Se invece le quantità sono diverse e il piano **non** li dichiara sostituti, crea due piatti separati: `Pasta + Pesce` e `Riso + Pesce`.

**Proteina** (seconda parte), nel tipo A da scegliere tra:

| Categoria | Cosa ci va |
|---|---|
| `Carne bianca` | pollo, tacchino, coniglio |
| `Carne rossa` | manzo, vitello, maiale, agnello, cavallo |
| `Pesce` | ogni pesce, molluschi, crostacei, tonno in scatola |
| `Uova` | uova intere, albumi, frittata |
| `Legumi` | ceci, lenticchie, fagioli, piselli, hummus |
| `Formaggio` | mozzarella, ricotta, fiocchi di latte, parmigiano… |
| `Salumi` | bresaola, prosciutto, fesa di tacchino |
| `Proteine vegetali` | tofu, tempeh, seitan |
| `Latticini` | yogurt, skyr, latte, se sono la proteina del pasto |

**Piatto senza carboidrato** (per esempio una cena di solo secondo): il nome è **solo la categoria**, come `Pesce` o `Carne bianca`. Il piatto contiene solo il gruppo della proteina.

**Opzioni semplici** (frutta, verdura, uno spuntino di un solo alimento): il nome è **solo l'alimento**, come `Mela`, `Zucchine` o `Mandorle`.

---

## 7. Calorie: dove e come

### 7.1 Dove vanno

| Voce | `calories` |
|---|---|
| Alimento singolo (frutta, verdura, olio, il carboidrato o la proteina dentro un piatto a scelta) | **sì**: le kcal di **quella** quantità |
| Piatto fisso (tipo B) | **sì**: la somma dei componenti |
| Piatto a scelta (tipo A, con `groups`) | **no**: non mettere il campo, le kcal arrivano dalle sotto-scelte |
| Integratori, acqua, caffè amaro, spezie | `null` |

L'app somma **solo** le calorie delle voci scelte davvero, comprese quelle dentro i piatti a scelta. Se metti le calorie sia sul piatto sia sulle sotto-scelte, vengono contate due volte.

### 7.2 Come si calcolano

1. Se il piano della nutrizionista indica le kcal, usa quelle.
2. Altrimenti: **kcal = kcal per 100 g × grammi ÷ 100**, arrotondato all'intero più vicino.
   - Pasta, riso, cereali, legumi secchi, carne e pesce: grammi **a crudo**, salvo quando il piano dice «cotto».
   - Le kcal per 100 g si prendono dalla tabella del § 12, che usa gli stessi valori del calcolatore dell'app, oppure dalle tabelle CREA.
3. Le calorie sono sempre **numeri interi senza virgolette**: `107`, non `"107"`, `107.4` o `"107 kcal"`.
4. Non stimare a caso: se un alimento non è in tabella e non hai un valore affidabile, metti `null`.

Esempio: merluzzo da 150 g, a 71 kcal per 100 g → 71 × 150 ÷ 100 = 106,5 → **107**.

### 7.3 Target dei pasti e del giorno

- `mealCalories.<pasto>` è la media delle combinazioni possibili di quel pasto, arrotondata alle decine. Per calcolarla:
  - in un gruppo `OR` si fa la media delle sue opzioni; per un piatto a scelta si usa la sua media interna;
  - un gruppo `AND` vale la somma delle sue opzioni;
  - si sommano tutti i gruppi del pasto.
- `calories` è il target giornaliero indicato dalla nutrizionista. Se il piano non lo dice, usa la **somma dei cinque `mealCalories`**.
- Se `calories` e la somma dei pasti differiscono di più del 10%, ricontrolla grammi e calorie.

### 7.4 Attenzione ai gruppi `MULTI`

Nei gruppi `MULTI` ogni opzione scelta conta per intero, anche quando si usa `totalGrams`. Se le opzioni hanno calorie e se ne scelgono tre, le calorie vengono contate tre volte.
- Per voci con calorie, come le verdure, usa un gruppo **`OR`**: una verdura a scelta, ciascuna con la sua porzione e le sue kcal.
- Usa `MULTI` solo per voci con `calories: null` oppure per voci davvero cumulabili, dove ogni opzione scelta si aggiunge alle altre.

---

## 8. Quantità

- È sempre **testo** con l'unità: `"80 g"`, `"200 ml"`, `"1 vasetto (125 g)"`, `"2 uova (110 g)"`, `"10 g (1 cucchiaio)"`.
- Quando l'unità non è in grammi, metti tra parentesi i grammi usati per il calcolo delle calorie.
- Per carboidrati e legumi secchi aggiungi `(peso crudo)` oppure `(peso cotto)`.
- Nei piatti fissi le quantità seguono l'ordine del nome: `"30 g + 100 g"`.

---

## 9. Icone

Usa una sola emoji per voce. Il piatto a scelta prende **l'icona della proteina**.

| Voce | Icona |
|---|---|
| Pesce | 🐟 (gamberi 🦐) |
| Carne bianca | 🍗 |
| Carne rossa | 🥩 |
| Uova | 🥚 |
| Legumi | 🫘 |
| Formaggio | 🧀 |
| Salumi | 🥓 |
| Proteine vegetali | 🌱 |
| Latticini / yogurt | 🥛 |
| Pasta | 🍝 |
| Riso | 🍚 |
| Pane | 🍞 |
| Patate | 🥔 |
| Farro, orzo, avena | 🌾 |
| Verdure | 🥦 🥒 🥬 🍅 🥕 🫛 |
| Frutta | 🍎 🍌 🍊 🍐 🥝 🍓 🫐 |
| Olio | 🫒 |
| Frutta secca | 🌰 |
| Integratori | 💊 |

---

## 10. Routine (facoltativa)

```json
"routine": {
  "waterTarget": 2.5,
  "waterNote": "Distribuita durante la giornata",
  "freeLimit": 1,
  "activities": ["Camminata", "Palestra"]
}
```

- `waterTarget`: litri d'acqua al giorno, con il punto per i decimali (`2.5`).
- `freeLimit`: pasti liberi per settimana (intero).
- `activities`: lista di nomi delle attività.
- `waterNote`: testo libero.
- Puoi anche aggiungere `items`, una lista di oggetti con `name`, `quantity` e `timing` (tutti testo), per le voci dell'allenamento come l'integratore pre-allenamento.

---

## 11. Limiti settimanali e voci da chiarire

- `"weeklyLimit": 1` su un'opzione: dopo una scelta in settimana, l'app la blocca fino alla settimana successiva. Mettilo sul **piatto** (per esempio `Pane + Carne rossa`) o sull'alimento a cui si riferisce il limite.
  - Il limite vale **solo per quella voce**. Se «carne rossa 1 volta a settimana» compare sia a pranzo sia a cena, sono due voci con due contatori separati. In quel caso mettila in un solo pasto oppure scrivi `1` su entrambe sapendo che si sommano.
- `"needsConfirmation": true`: la voce compare ma non si può confermare finché non la chiarisci nell'editor. Usalo solo se il piano è contraddittorio (per esempio «1 cucchiaio d'olio» in un punto e «20 g» in un altro).

---

## 12. Valori di riferimento (kcal per 100 g, o 100 ml per il latte)

Sono gli stessi valori del calcolatore «Aggiungi cibo» dell'app, così i conti tornano.

**Carboidrati (peso crudo)**

| Alimento | kcal / 100 g |
|---|---:|
| Pasta | 353 |
| Pasta integrale | 340 |
| Riso | 355 |
| Riso integrale | 350 |
| Farro | 335 |
| Orzo perlato | 319 |
| Couscous | 356 |
| Quinoa | 368 |
| Gnocchi di patate | 150 |
| Patate | 85 |
| Patate dolci | 86 |
| Pane | 267 |
| Pane integrale | 228 |
| Fette biscottate integrali | 386 |
| Gallette di riso | 381 |
| Fiocchi d’avena | 372 |
| Piadina | 331 |

**Proteine (peso crudo)**

| Alimento | kcal / 100 g |
|---|---:|
| Petto di pollo | 100 |
| Petto di tacchino | 107 |
| Manzo magro | 110 |
| Vitello | 92 |
| Lonza di maiale | 145 |
| Merluzzo | 71 |
| Orata | 121 |
| Branzino | 97 |
| Salmone fresco | 185 |
| Tonno al naturale | 103 |
| Pesce spada | 109 |
| Gamberi | 71 |
| Uovo | 128 |
| Albume | 43 |
| Bresaola | 151 |
| Prosciutto crudo | 268 |
| Ceci lessati | 120 |
| Lenticchie lessate | 116 |
| Fagioli lessati | 100 |
| Tofu | 80 |
| Ricotta | 146 |
| Mozzarella | 253 |
| Fiocchi di latte | 100 |
| Parmigiano | 387 |
| Yogurt greco 0% | 54 |

**Verdure**

| Alimento | kcal / 100 g |
|---|---:|
| Zucchine | 17 |
| Broccoli | 27 |
| Insalata | 15 |
| Spinaci | 31 |
| Fagiolini | 18 |
| Pomodori | 18 |
| Carote | 35 |
| Melanzane | 20 |
| Peperoni | 26 |
| Finocchi | 15 |

**Frutta, grassi e altro**

| Alimento | kcal / 100 g |
|---|---:|
| Mela | 52 |
| Banana | 89 |
| Arancia | 47 |
| Kiwi | 61 |
| Fragole | 32 |
| Mirtilli | 57 |
| Olio extravergine d’oliva | 899 |
| Burro | 717 |
| Mandorle | 590 |
| Noci | 654 |
| Burro di arachidi | 588 |
| Miele | 304 |
| Latte parzialmente scremato | 46 |

---

## 13. Controllo finale prima di incollare

- [ ] `format` è `germoglio-diet-v1`, l'`id` è nuovo e le date non si sovrappongono a un'altra dieta.
- [ ] `meals` ha tutte e cinque le chiavi, scritte esattamente come nel § 3.
- [ ] Ogni gruppo ha `name`, `type` (OR/AND/MULTI) e almeno un'opzione.
- [ ] I piatti di pranzo e cena si chiamano `Carboidrato + Proteina` (§ 6).
- [ ] I piatti a scelta **non** hanno `calories` e contengono `Carboidrato` + il gruppo della proteina.
- [ ] Tutte le altre voci hanno `calories` intere (oppure `null` per gli integratori).
- [ ] Nessun campo inventato. Niente virgole finali, niente commenti: il JSON deve essere valido.
- [ ] `calories` è circa uguale alla somma di `mealCalories` (entro il 10%).

---

## 14. Testo da dare a ChatGPT

Copia questo messaggio, poi allega o incolla il piano della nutrizionista **e questo file di regole**:

> Converti il piano alimentare che ti allego in un JSON per la mia app, seguendo **alla lettera** il file «Regole per scrivere il JSON di una dieta».
> - Formato `germoglio-diet-v1`; usa solo i campi elencati nelle regole.
> - id: `dieta-<mese>-<anno>`; date dal <GG/MM/AAAA> al <GG/MM/AAAA>.
> - A pranzo e cena ogni piatto si chiama «Carboidrato + Proteina» (es. «Pasta + Pesce», «Riso + Carne bianca»), come nel § 6. Usa il tipo A, con i gruppi «Carboidrato» e «<categoria proteina>», quando il piano lascia scegliere; usa il tipo B quando il piatto è fisso.
> - Le calorie vanno solo sulle voci senza `groups`, come numeri interi calcolati con kcal/100 g × grammi ÷ 100, peso a crudo, usando la tabella del § 12. I piatti a scelta non hanno `calories`.
> - Calcola `mealCalories` e `calories` come nel § 7.3.
> - Verdure in un gruppo OR «Verdure». Olio in un gruppo «Condimento»: AND se la quantità è sempre la stessa, OR con un'opzione per quantità se cambia secondo il piatto (§ 4).
> - Rispondi **solo** con il JSON, senza testo prima o dopo e senza commenti.
> - Se un punto del piano è ambiguo, metti `"needsConfirmation": true` su quella voce e non inventare.
