import { useState } from 'react';
import { SlidersHorizontal, Check } from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import type { Tag, TeamMember } from '@/lib/types';
import type { FilterState } from './TopBar';

interface Props {
  filters: FilterState;
  onFiltersChange: (next: FilterState) => void;
  tags: Tag[];
  members: TeamMember[];
}

export function FiltersDropdown({ filters, onFiltersChange, tags }: Props) {
  const [open, setOpen] = useState(false);

  const activeCount =
    (filters.scope !== 'all' ? 1 : 0) +
    (filters.priorityHigh ? 1 : 0) +
    (filters.dueWeek ? 1 : 0) +
    (filters.stale ? 1 : 0) +
    filters.tagIds.length;

  const update = (patch: Partial<FilterState>) =>
    onFiltersChange({ ...filters, ...patch });

  const clearAll = () =>
    onFiltersChange({
      scope: 'all',
      priorityHigh: false,
      dueWeek: false,
      stale: false,
      tagIds: [],
    });

  const toggleTag = (id: string) =>
    update({
      tagIds: filters.tagIds.includes(id)
        ? filters.tagIds.filter((t) => t !== id)
        : [...filters.tagIds, id],
    });

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger asChild>
        <button
          className="inline-flex items-center gap-[6px] rounded-lg transition-colors"
          style={{
            fontSize: 12,
            fontWeight: 500,
            padding: '7px 12px',
            background:
              activeCount > 0 ? 'rgba(210,230,50,0.1)' : 'rgba(15,51,51,0.5)',
            color:
              activeCount > 0 ? 'var(--owl-neon)' : 'var(--owl-text-muted)',
            border: 'none',
            cursor: 'pointer',
          }}
          aria-label="Filters"
        >
          <SlidersHorizontal className="w-3.5 h-3.5" />
          Filters
          {activeCount > 0 && (
            <span
              style={{
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 10,
                fontWeight: 500,
                padding: '0 5px',
                borderRadius: 10,
                background: 'var(--owl-neon)',
                color: '#0a2828',
              }}
            >
              {activeCount}
            </span>
          )}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        style={{
          width: 280,
          background: 'var(--owl-surface)',
          border: '1px solid var(--owl-border)',
          padding: 12,
        }}
      >
        <div className="flex items-center justify-between mb-2">
          <SectionLabel>Filters</SectionLabel>
          {activeCount > 0 && (
            <button
              onClick={clearAll}
              style={{
                fontSize: 11,
                color: 'var(--owl-text-muted)',
                background: 'transparent',
                border: 'none',
                cursor: 'pointer',
                padding: 0,
              }}
            >
              Clear all
            </button>
          )}
        </div>

        {/* Assignee scope */}
        <SectionLabel>Show</SectionLabel>
        <div className="flex flex-wrap gap-[5px] mb-[14px]">
          <Pill
            on={filters.scope === 'all'}
            onClick={() => update({ scope: 'all' })}
          >
            All
          </Pill>
          <Pill
            on={filters.scope === 'mine'}
            onClick={() => update({ scope: 'mine' })}
          >
            Mine
          </Pill>
          <Pill
            on={filters.scope === 'unassigned'}
            onClick={() => update({ scope: 'unassigned' })}
          >
            Unassigned
          </Pill>
        </div>

        {/* Priority */}
        <SectionLabel>Priority</SectionLabel>
        <Row
          on={filters.priorityHigh}
          onClick={() => update({ priorityHigh: !filters.priorityHigh })}
        >
          High priority only
        </Row>

        {/* Due */}
        <div className="mt-[6px]">
          <SectionLabel>Due</SectionLabel>
          <Row
            on={filters.dueWeek}
            onClick={() => update({ dueWeek: !filters.dueWeek })}
          >
            Due this week
          </Row>
          <Row
            on={filters.stale}
            onClick={() => update({ stale: !filters.stale })}
          >
            Stale ≥ 3 days
          </Row>
        </div>

        {/* Tags */}
        {tags.length > 0 && (
          <div className="mt-[6px]">
            <SectionLabel>Tags</SectionLabel>
            <div className="flex flex-wrap gap-[5px] mt-1 max-h-[140px] overflow-y-auto">
              {tags.map((t) => (
                <Pill
                  key={t.id}
                  on={filters.tagIds.includes(t.id)}
                  onClick={() => toggleTag(t.id)}
                >
                  #{t.name}
                </Pill>
              ))}
            </div>
          </div>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="mb-1"
      style={{
        fontSize: 9,
        fontWeight: 600,
        letterSpacing: '2px',
        textTransform: 'uppercase',
        color: 'var(--owl-text-label)',
      }}
    >
      {children}
    </div>
  );
}

function Pill({
  on,
  onClick,
  children,
}: {
  on?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className="rounded-full transition-colors"
      style={{
        fontSize: 11,
        fontWeight: 500,
        padding: '5px 10px',
        background: on ? 'rgba(210,230,50,0.1)' : 'rgba(15,51,51,0.5)',
        color: on ? 'var(--owl-neon)' : 'var(--owl-text-muted)',
        border: 'none',
        cursor: 'pointer',
      }}
    >
      {children}
    </button>
  );
}

function Row({
  on,
  onClick,
  children,
}: {
  on?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center justify-between gap-2 transition-colors rounded-md"
      style={{
        fontSize: 13,
        padding: '6px 8px',
        background: 'transparent',
        color: on ? 'var(--owl-text-primary)' : 'var(--owl-text-secondary)',
        border: 'none',
        cursor: 'pointer',
        textAlign: 'left',
      }}
      onMouseEnter={(e) =>
        (e.currentTarget.style.background = 'rgba(30,90,80,0.14)')
      }
      onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
    >
      <span>{children}</span>
      {on && <Check className="w-3.5 h-3.5" style={{ color: 'var(--owl-neon)' }} />}
    </button>
  );
}
