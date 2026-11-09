import { useEffect, useMemo, useState } from 'react';
import { Activity, AlertTriangle, ArrowLeftRight, BarChart3, CalendarDays, Package, RefreshCw, TrendingDown, Trash2 } from 'lucide-react';
import { supabase } from './supabase';
import type { Lang } from './i18n';

type Row = Record<string, any>;
type Shortage = { product: Row; pl: Row; shortage: number };
type RawMovement = {
  id: string; product_id: string; location_id: string; destination_location_id: string | null;
  transfer_group_id: string | null; movement_type: string; quantity_change: number | string;
  reason: string | null; notes: string | null; created_at: string;
};
type Movement = {
  id: string; product_id: string; type: 'consumption' | 'waste' | 'transfer' | 'adjustment' | 'other';
  quantity: number; signedQuantity: number; locationIds: string[]; sourceLocationId: string | null;
  destinationLocationId: string | null; reason: string | null; notes: string | null; created_at: string;
};
type Props = { orgId: string; lang: Lang; products: Row[]; locations: Row[]; shortages: Shortage[] };

const PAGE_SIZE = 500;
const MAX_ROWS = 20000;

function localDate(date: Date) {
  return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('-');
}
function offsetDate(days: number) {
  const date = new Date(); date.setHours(0, 0, 0, 0); date.setDate(date.getDate() - days); return localDate(date);
}
function startISO(value: string) { return new Date(value + 'T00:00:00').toISOString(); }
function endISO(value: string) { const date = new Date(value + 'T00:00:00'); date.setDate(date.getDate() + 1); return date.toISOString(); }

function normalise(rows: RawMovement[]): Movement[] {
  const regular: Movement[] = [];
  const transfers = new Map<string, Movement>();
  for (const row of rows) {
    const kind = String(row.movement_type || 'adjustment');
    if (kind === 'transfer_in' || kind === 'transfer_out') {
      const key = row.transfer_group_id || row.id;
      const out = kind === 'transfer_out';
      const source = out ? row.location_id : row.destination_location_id;
      const destination = out ? row.destination_location_id : row.location_id;
      const current = transfers.get(key);
      if (current) {
        current.quantity = Math.max(current.quantity, Math.abs(Number(row.quantity_change || 0)));
        current.locationIds = [...new Set([current.sourceLocationId, current.destinationLocationId].filter(Boolean) as string[])];
      } else {
        transfers.set(key, {
          id: key, product_id: row.product_id, type: 'transfer', quantity: Math.abs(Number(row.quantity_change || 0)),
          signedQuantity: -Math.abs(Number(row.quantity_change || 0)), locationIds: [...new Set([source, destination].filter(Boolean) as string[])],
          sourceLocationId: source || null, destinationLocationId: destination || null,
          reason: row.reason, notes: row.notes, created_at: row.created_at,
        });
      }
      continue;
    }
    const type: Movement['type'] = kind === 'consumption' ? 'consumption' : kind === 'waste' ? 'waste' : kind === 'adjustment' ? 'adjustment' : 'other';
    regular.push({
      id: row.id, product_id: row.product_id, type, quantity: Math.abs(Number(row.quantity_change || 0)),
      signedQuantity: Number(row.quantity_change || 0), locationIds: row.location_id ? [row.location_id] : [],
      sourceLocationId: row.location_id || null, destinationLocationId: null, reason: row.reason,
      notes: row.notes, created_at: row.created_at,
    });
  }
  return [...regular, ...transfers.values()].sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
}

export default function DashboardAnalytics({ orgId, lang, products, locations, shortages }: Props) {
  const pt = lang === 'pt';
  const [period, setPeriod] = useState('30d');
  const [fromDate, setFromDate] = useState(() => offsetDate(29));
  const [toDate, setToDate] = useState(() => localDate(new Date()));
  const [productId, setProductId] = useState('all');
  const [locationId, setLocationId] = useState('all');
  const [kind, setKind] = useState('all');
  const [rows, setRows] = useState<RawMovement[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [truncated, setTruncated] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const label = {
    heading: pt ? 'Análises do estoque' : 'Stock analytics', period: pt ? 'Período' : 'Period',
    product: pt ? 'Produto' : 'Product', allProducts: pt ? 'Todos os produtos' : 'All products',
    location: pt ? 'Localização' : 'Location', allLocations: pt ? 'Todas as localizações' : 'All locations',
    movement: pt ? 'Movimentação' : 'Movement type', allMovements: pt ? 'Todas as movimentações' : 'All movements',
    last7: pt ? 'Últimos 7 dias' : 'Last 7 days', last30: pt ? 'Últimos 30 dias' : 'Last 30 days',
    last90: pt ? 'Últimos 90 dias' : 'Last 90 days', custom: pt ? 'Personalizado' : 'Custom range',
    from: pt ? 'De' : 'From', to: pt ? 'Até' : 'To', active: pt ? 'Produtos ativos' : 'Active products',
    low: pt ? 'Itens abaixo do mínimo' : 'Below-minimum items', consumption: pt ? 'Registros de consumo' : 'Consumption records',
    waste: pt ? 'Registros de desperdício' : 'Waste records', trend: pt ? 'Movimentações por período' : 'Movement activity over time',
    trendHint: pt ? 'Comparação pelo número de operações, sem somar unidades diferentes.' : 'Operation counts are compared; different units are never added together.',
    consumptionByProduct: pt ? 'Consumo por produto' : 'Consumption by product', wasteByProduct: pt ? 'Desperdício por produto' : 'Waste by product',
    wasteReasons: pt ? 'Motivos de desperdício' : 'Waste reasons', locationActivity: pt ? 'Atividade por localização' : 'Activity by location',
    consumptionWasteByLocation: pt ? 'Consumo e desperdício por localização' : 'Consumption & waste by location',
    consumptionEvents: pt ? 'registros de consumo' : 'consumption events', wasteEvents: pt ? 'registros de desperdício' : 'waste events',
    noWasteReasons: pt ? 'Os motivos aparecerão quando houver desperdícios registrados.' : 'Reasons will appear when waste is recorded.',
    noConsumptionWaste: pt ? 'Sem registros de consumo ou desperdício neste período.' : 'No consumption or waste events in this period.',
    reason: pt ? 'Motivo / observação' : 'Reason / note',
    alerts: pt ? 'Alertas de reposição' : 'Replenishment alerts',
    recent: pt ? 'Movimentações recentes' : 'Recent movements', date: pt ? 'Data' : 'Date', item: pt ? 'Produto' : 'Product',
    type: pt ? 'Tipo' : 'Type', locationCol: pt ? 'Localização' : 'Location', quantity: pt ? 'Quantidade' : 'Quantity',
    none: pt ? 'Nenhuma movimentação registrada neste período.' : 'No movements recorded in this period.',
    noneWaste: pt ? 'Nenhum desperdício registrado neste período.' : 'No waste recorded in this period.',
    noneConsumption: pt ? 'Nenhum consumo registrado neste período.' : 'No consumption recorded in this period.',
    noneLocation: pt ? 'Sem atividade nas localizações selecionadas.' : 'No activity for selected locations.',
    noneAlerts: pt ? 'Nenhum item abaixo do estoque mínimo.' : 'No items are below minimum stock.',
    loading: pt ? 'Carregando movimentações…' : 'Loading stock movements…', retry: pt ? 'Tentar novamente' : 'Try again',
    adjust: pt ? 'Ajuste de estoque' : 'Stock adjustment', transfer: pt ? 'Transferência' : 'Transfer',
    open: pt ? 'Saldo inicial' : 'Opening balance', records: pt ? 'operações' : 'events',
    perProduct: pt ? 'Quantidades detalhadas por produto e unidade.' : 'Quantities are detailed separately by product and unit.',
    capped: pt ? 'Limite de 20.000 movimentações atingido. Reduza o intervalo para analisar todo o período.' : '20,000-movement limit reached. Narrow the date range to analyse the full period.',
    invalid: pt ? 'A data inicial deve ser anterior ou igual à data final.' : 'The start date must be on or before the end date.',
  };

  useEffect(() => {
    if (period === 'custom') return;
    const end = new Date(); const start = new Date(end); start.setHours(0, 0, 0, 0);
    start.setDate(start.getDate() - (period === '7d' ? 6 : period === '90d' ? 89 : 29));
    setFromDate(localDate(start)); setToDate(localDate(end));
  }, [period]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!supabase || !orgId || !fromDate || !toDate) { setRows([]); return; }
      if (fromDate > toDate) { setError(label.invalid); setRows([]); return; }
      setLoading(true); setError(''); setTruncated(false);
      try {
        const all: RawMovement[] = [];
        for (let offset = 0; offset < MAX_ROWS; offset += PAGE_SIZE) {
          let query = supabase.from('stock_movements')
            .select('id,product_id,location_id,destination_location_id,transfer_group_id,movement_type,quantity_change,reason,notes,created_at')
            .eq('organization_id', orgId).gte('created_at', startISO(fromDate)).lt('created_at', endISO(toDate))
            .order('created_at', { ascending: false }).order('id', { ascending: false });
          if (productId !== 'all') query = query.eq('product_id', productId);
          if (locationId !== 'all') query = query.or('location_id.eq.' + locationId + ',destination_location_id.eq.' + locationId);
          const { data, error: queryError } = await query.range(offset, offset + PAGE_SIZE - 1);
          if (queryError) throw queryError;
          const page = (data || []) as RawMovement[]; all.push(...page);
          if (page.length < PAGE_SIZE) break;
          if (offset + PAGE_SIZE >= MAX_ROWS) { if (!cancelled) setTruncated(true); break; }
        }
        if (!cancelled) setRows(all);
      } catch (loadError: any) {
        if (!cancelled) { setError(loadError?.message || (pt ? 'Não foi possível carregar os dados.' : 'Could not load analytics data.')); setRows([]); }
      } finally { if (!cancelled) setLoading(false); }
    }
    load(); return () => { cancelled = true; };
  }, [orgId, fromDate, toDate, productId, locationId, refreshKey, pt, label.invalid]);

  const movements = useMemo(() => normalise(rows).filter(row => kind === 'all' || row.type === kind), [rows, kind]);
  const productMap = useMemo(() => new Map(products.map(row => [row.id, row])), [products]);
  const locationMap = useMemo(() => new Map(locations.map(row => [row.id, row])), [locations]);
  const matchingShortages = shortages.filter(row => (productId === 'all' || row.product.id === productId) && (locationId === 'all' || row.pl.location_id === locationId));
  const consumption = movements.filter(row => row.type === 'consumption');
  const waste = movements.filter(row => row.type === 'waste');
  const selectedProduct = productId === 'all' ? null : productMap.get(productId);
  const numberFormat = useMemo(() => new Intl.NumberFormat(pt ? 'pt-BR' : 'en-IE', { maximumFractionDigits: 2 }), [pt]);
  const qty = (value: number, unit?: string) => numberFormat.format(value) + (unit ? ' ' + unit : '');
  const dateTime = (value: string) => new Date(value).toLocaleString(pt ? 'pt-BR' : 'en-IE', { dateStyle: 'medium', timeStyle: 'short' });

  const ranking = (items: Movement[]) => {
    const map = new Map<string, { name: string; unit: string; total: number; count: number }>();
    items.forEach(row => {
      const product = productMap.get(row.product_id);
      const old = map.get(row.product_id) || { name: product?.name || (pt ? 'Produto arquivado' : 'Archived product'), unit: product?.base_unit || '', total: 0, count: 0 };
      old.total += row.quantity; old.count += 1; map.set(row.product_id, old);
    });
    return [...map.entries()].map(([id, item]) => ({ id, ...item })).sort((a, b) => b.total - a.total).slice(0, 5);
  };
  const consumptionRank = ranking(consumption);
  const wasteRank = ranking(waste);
  const wasteReasonStats = useMemo(() => {
    const map = new Map<string, number>();
    waste.forEach(row => {
      const reason = String(row.notes || '').trim() || (pt ? 'Motivo não informado' : 'Reason not specified');
      map.set(reason, (map.get(reason) || 0) + 1);
    });
    return [...map.entries()].map(([reason, count]) => ({ reason, count })).sort((a, b) => b.count - a.count).slice(0, 6);
  }, [waste, pt]);

  const locationCounts = new Map<string, number>();
  movements.forEach(row => new Set(row.locationIds).forEach(id => locationCounts.set(id, (locationCounts.get(id) || 0) + 1)));
  const locationStats = [...locationCounts.entries()].map(([id, count]) => ({ id, name: locationMap.get(id)?.name || (pt ? 'Local arquivado' : 'Archived location'), count })).sort((a, b) => b.count - a.count);
  const locationTypeMap = new Map<string, { consumption: number; waste: number }>();
  [...consumption, ...waste].forEach(row => row.locationIds.forEach(id => {
    const current = locationTypeMap.get(id) || { consumption: 0, waste: 0 };
    if (row.type === 'consumption') current.consumption += 1;
    if (row.type === 'waste') current.waste += 1;
    locationTypeMap.set(id, current);
  }));
  const locationTypeStats = [...locationTypeMap.entries()].map(([id, counts]) => ({ id, name: locationMap.get(id)?.name || (pt ? 'Local arquivado' : 'Archived location'), ...counts, total: counts.consumption + counts.waste })).sort((a, b) => b.total - a.total);
  const maxLocationTypeCount = Math.max(1, ...locationTypeStats.map(row => row.total));

  const buckets = useMemo(() => {
    if (!fromDate || !toDate || fromDate > toDate) return [];
    const start = new Date(fromDate + 'T00:00:00'); const end = new Date(toDate + 'T00:00:00');
    const days = Math.max(1, Math.round((end.getTime() - start.getTime()) / 86400000) + 1); const weekly = days > 45;
    const map = new Map<string, { key: string; label: string; consumption: number; waste: number; adjustment: number; transfer: number }>();
    for (let i = 0; i < days; i++) {
      const date = new Date(start); date.setDate(date.getDate() + i);
      const bucketDate = new Date(date); if (weekly) bucketDate.setDate(bucketDate.getDate() - ((bucketDate.getDay() + 6) % 7));
      const key = localDate(bucketDate);
      if (!map.has(key)) map.set(key, { key, label: bucketDate.toLocaleDateString(pt ? 'pt-BR' : 'en-IE', { day: '2-digit', month: 'short' }), consumption: 0, waste: 0, adjustment: 0, transfer: 0 });
    }
    movements.forEach(row => {
      const date = new Date(row.created_at); if (weekly) date.setDate(date.getDate() - ((date.getDay() + 6) % 7));
      const bucket = map.get(localDate(date)); if (!bucket) return;
      if (row.type === 'consumption') bucket.consumption++;
      else if (row.type === 'waste') bucket.waste++;
      else if (row.type === 'transfer') bucket.transfer++;
      else bucket.adjustment++;
    });
    return [...map.values()].sort((a, b) => a.key.localeCompare(b.key));
  }, [fromDate, toDate, movements, pt]);
  const maxBucket = Math.max(1, ...buckets.map(row => row.consumption + row.waste + row.adjustment + row.transfer));
  const legend = [
    { key: 'consumption', label: pt ? 'Consumo' : 'Consumption', color: '#269b75' },
    { key: 'waste', label: pt ? 'Desperdício' : 'Waste', color: '#d58a47' },
    { key: 'adjustment', label: label.adjust, color: '#6888d8' },
    { key: 'transfer', label: label.transfer, color: '#9a78c8' },
  ] as const;
  const typeName = (row: Movement) => row.type === 'consumption' ? (pt ? 'Consumo' : 'Consumption') : row.type === 'waste' ? (pt ? 'Desperdício' : 'Waste') : row.type === 'transfer' ? label.transfer : row.reason === 'opening_balance' ? label.open : label.adjust;
  const where = (row: Movement) => row.type === 'transfer'
    ? (locationMap.get(row.sourceLocationId || '')?.name || '—') + ' → ' + (locationMap.get(row.destinationLocationId || '')?.name || '—')
    : locationMap.get(row.sourceLocationId || '')?.name || '—';
  const reasonText = (row: Movement) => {
    const value = String(row.notes || row.reason || '').trim();
    if (!value || value === row.type || value === 'adjustment') return '—';
    if (value === 'opening_balance') return label.open;
    if (value === 'stock_check') return pt ? 'Contagem de estoque' : 'Stock check';
    return value.replace(/_/g, ' ');
  };
  const productQtyHint = selectedProduct ? qty(consumption.reduce((sum, row) => sum + row.quantity, 0), selectedProduct.base_unit) : label.perProduct;
  const wasteQtyHint = selectedProduct ? qty(waste.reduce((sum, row) => sum + row.quantity, 0), selectedProduct.base_unit) : label.perProduct;

  return <section className="analytics-shell">
    <div className="analytics-section-head"><div><p className="eyebrow">{label.heading.toUpperCase()}</p><h2>{label.heading}</h2><p>{label.trendHint}</p></div>
      <button className="analytics-refresh" type="button" onClick={() => setRefreshKey(value => value + 1)} disabled={loading}><RefreshCw size={15} className={loading ? 'analytics-spinning' : ''} />{pt ? 'Atualizar' : 'Refresh'}</button>
    </div>
    <div className="analytics-filters">
      <label className="analytics-filter-field"><span><CalendarDays size={14} />{label.period}</span><select value={period} onChange={event => setPeriod(event.target.value)}><option value="7d">{label.last7}</option><option value="30d">{label.last30}</option><option value="90d">{label.last90}</option><option value="custom">{label.custom}</option></select></label>
      {period === 'custom' && <><label className="analytics-filter-field"><span>{label.from}</span><input type="date" value={fromDate} max={toDate} onChange={event => setFromDate(event.target.value)} /></label><label className="analytics-filter-field"><span>{label.to}</span><input type="date" value={toDate} min={fromDate} max={localDate(new Date())} onChange={event => setToDate(event.target.value)} /></label></>}
      <label className="analytics-filter-field"><span><Package size={14} />{label.product}</span><select value={productId} onChange={event => setProductId(event.target.value)}><option value="all">{label.allProducts}</option>{products.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
      <label className="analytics-filter-field"><span><Activity size={14} />{label.location}</span><select value={locationId} onChange={event => setLocationId(event.target.value)}><option value="all">{label.allLocations}</option>{locations.map(row => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
      <label className="analytics-filter-field"><span><ArrowLeftRight size={14} />{label.movement}</span><select value={kind} onChange={event => setKind(event.target.value)}><option value="all">{label.allMovements}</option><option value="consumption">{pt ? 'Consumo' : 'Consumption'}</option><option value="waste">{pt ? 'Desperdício' : 'Waste'}</option><option value="transfer">{label.transfer}</option><option value="adjustment">{label.adjust}</option></select></label>
    </div>
    {loading && <div className="analytics-loading"><span className="analytics-spinner" />{label.loading}</div>}
    {error && <div className="analytics-error" role="alert">{error}<button type="button" onClick={() => setRefreshKey(value => value + 1)}>{label.retry}</button></div>}
    {truncated && <div className="analytics-note">{label.capped}</div>}
    <div className="analytics-kpi-grid">
      <AnalyticsStat icon={Package} label={label.active} value={productId === 'all' ? products.length : (selectedProduct ? 1 : 0)} tone="blue" />
      <AnalyticsStat icon={AlertTriangle} label={label.low} value={matchingShortages.length} tone={matchingShortages.length ? 'orange' : 'green'} />
      <AnalyticsStat icon={TrendingDown} label={label.consumption} value={consumption.length} sub={productQtyHint} tone="green" />
      <AnalyticsStat icon={Trash2} label={label.waste} value={waste.length} sub={wasteQtyHint} tone="orange" />
    </div>
    <div className="analytics-main-grid">
      <section className="analytics-panel analytics-trend-panel"><div className="analytics-panel-head"><div><h3>{label.trend}</h3><p>{movements.length} {label.records}</p></div><BarChart3 size={19} /></div>
        {!loading && !movements.length ? <AnalyticsEmpty icon={Activity} text={label.none} /> : <div className="analytics-chart-wrap">
          <div className="analytics-legend">{legend.map(item => <span key={item.key}><i style={{ background: item.color }} />{item.label}</span>)}</div>
          <svg viewBox="0 0 760 220" role="img" aria-label={label.trend} className="analytics-chart">
            {[0, 1, 2, 3].map(step => { const y = 174 - step * 48; return <g key={step}><line x1="42" y1={y} x2="742" y2={y} stroke="#e8edf4" strokeDasharray="4 5" /><text x="31" y={y + 4} textAnchor="end" fill="#8b96a8" fontSize="10">{Math.round(maxBucket * step / 3)}</text></g>; })}
            {buckets.map((bucket, index) => { const slot = 700 / Math.max(1, buckets.length); const width = Math.max(3, Math.min(22, slot * .62)); const x = 42 + index * slot + (slot - width) / 2; let y = 174;
              const values = legend.map(item => ({ key: item.key, value: bucket[item.key], color: item.color }));
              return <g key={bucket.key}>{values.map(segment => { const height = segment.value ? Math.max(1.5, segment.value / maxBucket * 144) : 0; y -= height; return height ? <rect key={segment.key} x={x} y={y} width={width} height={height} rx="2" fill={segment.color} /> : null; })}
                {(index % Math.max(1, Math.ceil(buckets.length / 7)) === 0 || index === buckets.length - 1) && <text x={x + width / 2} y="198" textAnchor="middle" fill="#8b96a8" fontSize="10">{bucket.label}</text>}</g>; })}
          </svg>
        </div>}
      </section>
      <RankPanel title={label.consumptionByProduct} items={consumptionRank} empty={label.noneConsumption} events={label.records} formatQty={qty} icon={TrendingDown} tone="green" />
      <RankPanel title={label.wasteByProduct} items={wasteRank} empty={label.noneWaste} events={label.records} formatQty={qty} icon={Trash2} tone="orange" />
      <section className="analytics-panel"><div className="analytics-panel-head"><div><h3>{label.wasteReasons}</h3><p>{waste.reduce((sum, row) => sum + 1, 0)} {label.records}</p></div><Trash2 size={18} /></div>
        {wasteReasonStats.length ? <div className="analytics-reason-list">{wasteReasonStats.map((row, index) => <div className="analytics-reason-row" key={row.reason}><span>{row.reason}</span><strong>{row.count}</strong></div>)}</div> : <AnalyticsEmpty icon={Trash2} text={label.noWasteReasons} />}
      </section>
      <section className="analytics-panel"><div className="analytics-panel-head"><div><h3>{label.locationActivity}</h3><p>{pt ? 'Operações que envolveram cada local' : 'Operations involving each location'}</p></div><Activity size={18} /></div>
        {locationStats.length ? <div className="analytics-location-list">{locationStats.slice(0, 6).map(row => <div className="analytics-location-row" key={row.id}><div className="analytics-location-label"><b>{row.name}</b><span>{row.count} {label.records}</span></div><div className="analytics-progress"><span style={{ width: (row.count / Math.max(1, locationStats[0].count) * 100) + '%' }} /></div></div>)}</div> : <AnalyticsEmpty icon={Activity} text={label.noneLocation} />}
      </section>
      <section className="analytics-panel"><div className="analytics-panel-head"><div><h3>{label.consumptionWasteByLocation}</h3><p>{label.trendHint}</p></div><Activity size={18} /></div>
        <div className="analytics-legend"><span><i style={{ background: '#269b75' }} />{label.consumption}</span><span><i style={{ background: '#d58a47' }} />{label.waste}</span></div>
        {locationTypeStats.length ? <div className="analytics-location-type-list">{locationTypeStats.map(row => <div className="analytics-location-type-row" key={row.id}><div className="analytics-location-label"><b>{row.name}</b><span>{row.total} {label.records}</span></div><div className="analytics-type-track"><span className="analytics-track-consumption" style={{ width: (row.consumption / maxLocationTypeCount * 100) + '%' }} /></div><div className="analytics-type-track"><span className="analytics-track-waste" style={{ width: (row.waste / maxLocationTypeCount * 100) + '%' }} /></div><small>{row.consumption} {label.consumptionEvents} · {row.waste} {label.wasteEvents}</small></div>)}</div> : <AnalyticsEmpty icon={Activity} text={label.noConsumptionWaste} />}
      </section>
      <section className="analytics-panel"><div className="analytics-panel-head"><div><h3>{label.alerts}</h3><p>{matchingShortages.length} {pt ? 'itens precisam de atenção' : 'items need attention'}</p></div><AlertTriangle size={18} /></div>
        {matchingShortages.length ? <div className="analytics-alert-list">{matchingShortages.slice(0, 6).map((row, index) => <div className="analytics-alert-row" key={row.product.id + row.pl.location_id + index}><span className="analytics-alert-icon"><AlertTriangle size={15} /></span><div className="analytics-alert-main"><b>{row.product.name}</b><small>{row.pl.locations?.name || locationMap.get(row.pl.location_id)?.name || '—'}</small></div><strong>-{qty(row.shortage, row.product.base_unit)}</strong></div>)}{matchingShortages.length > 6 && <small className="analytics-more-alerts">+{matchingShortages.length - 6} {pt ? 'outros itens' : 'more items'}</small>}</div> : <AnalyticsEmpty icon={Package} text={label.noneAlerts} />}
      </section>
    </div>
    <section className="analytics-panel analytics-recent-panel"><div className="analytics-panel-head"><div><h3>{label.recent}</h3><p>{movements.length} {label.records}</p></div><Activity size={18} /></div>
      {!loading && !movements.length ? <AnalyticsEmpty icon={Activity} text={label.none} /> : <div className="analytics-table-wrap"><table className="analytics-table"><thead><tr><th>{label.date}</th><th>{label.item}</th><th>{label.type}</th><th>{label.locationCol}</th><th>{label.quantity}</th><th>{label.reason}</th></tr></thead><tbody>
        {movements.slice(0, 12).map(row => { const product = productMap.get(row.product_id); const quantity = row.type === 'adjustment' ? row.signedQuantity : row.quantity;
          const typeClass = row.type === 'other' ? 'adjustment' : row.type;
          return <tr key={row.id}><td>{dateTime(row.created_at)}</td><td><b>{product?.name || (pt ? 'Produto arquivado' : 'Archived product')}</b><small>{product?.sku || ''}</small></td><td><span className={'analytics-type analytics-type-' + typeClass}>{typeName(row)}</span></td><td>{where(row)}</td><td className={quantity < 0 ? 'analytics-qty-negative' : ''}>{qty(quantity, product?.base_unit)}</td><td>{reasonText(row)}</td></tr>;
        })}
      </tbody></table></div>}
    </section>
  </section>;
}

function AnalyticsStat({ icon: Icon, label, value, sub, tone }: any) {
  return <div className="analytics-kpi"><div className="analytics-kpi-top"><span>{label}</span><i className={'analytics-kpi-icon ' + tone}><Icon size={17} /></i></div><strong>{value}</strong>{sub && <small>{sub}</small>}</div>;
}
function AnalyticsEmpty({ icon: Icon, text }: any) { return <div className="analytics-empty"><Icon size={23} /><span>{text}</span></div>; }
function RankPanel({ title, items, empty, events, formatQty, icon: Icon, tone }: any) {
  return <section className="analytics-panel"><div className="analytics-panel-head"><div><h3>{title}</h3><p>{items.reduce((sum: number, row: any) => sum + row.count, 0)} {events}</p></div><Icon size={18} /></div>
    {items.length ? <div className="analytics-ranked-list">{items.map((row: any, index: number) => <div className="analytics-ranked-row" key={row.id}><span className="analytics-rank">{index + 1}</span><div className="analytics-ranked-main"><b>{row.name}</b><small>{row.count} {events}</small></div><strong className={'analytics-rank-value ' + tone}>{formatQty(row.total, row.unit)}</strong></div>)}</div> : <AnalyticsEmpty icon={Icon} text={empty} />}
  </section>;
}
