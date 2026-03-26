import { useState } from 'react';
import { ArrowLeft, Plus, Pencil, Trash2, Zap } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { useRules } from '@/hooks/useRules';
import { useTasks } from '@/hooks/useTasks';
import { useAuth } from '@/hooks/useAuth';
import { COLUMNS } from '@/lib/constants';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';

const TRIGGER_TYPES = [
  { value: 'task_assigned', label: 'A task is assigned to' },
  { value: 'task_moved', label: 'A task is moved to' },
  { value: 'task_created', label: 'A task is created' },
  { value: 'task_completed', label: 'A task is completed' },
  { value: 'tag_added', label: 'A tag is added to a task' },
];

const ACTION_TYPES = [
  { value: 'assign_user', label: 'Assign task to' },
  { value: 'move_to_column', label: 'Move task to' },
  { value: 'add_tag', label: 'Add a tag' },
  { value: 'send_notification', label: 'Send notification to' },
  { value: 'remove_assignee', label: 'Remove assignee' },
];

export default function RulesPage() {
  const navigate = useNavigate();
  const { rules, createRule, updateRule, deleteRule, toggleRule } = useRules();
  const { members, tags } = useTasks();
  const { member } = useAuth();
  const [showBuilder, setShowBuilder] = useState(false);
  const [editingRule, setEditingRule] = useState<string | null>(null);

  const [name, setName] = useState('');
  const [triggerType, setTriggerType] = useState('');
  const [triggerConfig, setTriggerConfig] = useState<Record<string, any>>({});
  const [actionType, setActionType] = useState('');
  const [actionConfig, setActionConfig] = useState<Record<string, any>>({});

  const resetForm = () => {
    setName('');
    setTriggerType('');
    setTriggerConfig({});
    setActionType('');
    setActionConfig({});
    setEditingRule(null);
  };

  const openEdit = (rule: any) => {
    setName(rule.name);
    setTriggerType(rule.trigger_type);
    setTriggerConfig(rule.trigger_config);
    setActionType(rule.action_type);
    setActionConfig(rule.action_config);
    setEditingRule(rule.id);
    setShowBuilder(true);
  };

  const handleSave = () => {
    if (!name.trim() || !triggerType || !actionType) {
      toast.error('Please fill all required fields');
      return;
    }
    const data = {
      name: name.trim(),
      trigger_type: triggerType,
      trigger_config: triggerConfig,
      action_type: actionType,
      action_config: actionConfig,
      active: true,
      created_by: member?.user_id || null,
    };
    if (editingRule) {
      updateRule.mutate({ id: editingRule, ...data }, { onSuccess: () => { setShowBuilder(false); resetForm(); toast.success('Rule updated'); } });
    } else {
      createRule.mutate(data, { onSuccess: () => { setShowBuilder(false); resetForm(); toast.success('Rule created'); } });
    }
  };

  const getTriggerSummary = (type: string, config: Record<string, any>) => {
    const label = TRIGGER_TYPES.find((t) => t.value === type)?.label || type;
    if (type === 'task_assigned' && config.user_id) {
      return `${label} ${members.find((m) => m.id === config.user_id)?.name || 'someone'}`;
    }
    if (type === 'task_moved' && config.column) {
      return `${label} ${COLUMNS.find((c) => c.id === config.column)?.label || config.column}`;
    }
    return label;
  };

  const getActionSummary = (type: string, config: Record<string, any>) => {
    const label = ACTION_TYPES.find((t) => t.value === type)?.label || type;
    if (type === 'assign_user' && config.user_id) {
      return `${label} ${members.find((m) => m.id === config.user_id)?.name || 'someone'}`;
    }
    if (type === 'move_to_column' && config.column) {
      return `${label} ${COLUMNS.find((c) => c.id === config.column)?.label || config.column}`;
    }
    if (type === 'add_tag' && config.tag_id) {
      return `${label} #${tags.find((t) => t.id === config.tag_id)?.name || ''}`;
    }
    return label;
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="border-b border-border bg-card px-5 py-3 flex items-center gap-3">
        <Button variant="ghost" size="sm" className="h-7 w-7 p-0" onClick={() => navigate('/')}>
          <ArrowLeft className="w-4 h-4" />
        </Button>
        <Zap className="w-4 h-4 text-muted-foreground" />
        <h1 className="text-sm font-semibold text-foreground">Rules & Automation</h1>
        <div className="flex-1" />
        <Button size="sm" className="h-7 text-[11px] gap-1" onClick={() => { resetForm(); setShowBuilder(true); }}>
          <Plus className="w-3 h-3" /> New Rule
        </Button>
      </div>

      <div className="max-w-3xl mx-auto p-6 space-y-3">
        {rules.length === 0 && (
          <div className="text-center py-12">
            <Zap className="w-8 h-8 text-muted-foreground mx-auto mb-2" />
            <p className="text-sm text-muted-foreground">No rules yet. Create one to automate your workflow.</p>
          </div>
        )}
        {rules.map((rule) => (
          <div key={rule.id} className="bg-card border border-border rounded-lg p-4 flex items-center gap-4">
            <div className="flex-1 min-w-0">
              <p className="text-xs font-medium text-foreground">{rule.name}</p>
              <p className="text-[10px] text-muted-foreground mt-0.5">
                If: {getTriggerSummary(rule.trigger_type, rule.trigger_config)} → Then: {getActionSummary(rule.action_type, rule.action_config)}
              </p>
            </div>
            <Switch
              checked={rule.active}
              onCheckedChange={(checked) => toggleRule.mutate({ id: rule.id, active: checked })}
            />
            <Button variant="ghost" size="sm" className="h-7 w-7 p-0" onClick={() => openEdit(rule)}>
              <Pencil className="w-3 h-3" />
            </Button>
            <Button variant="ghost" size="sm" className="h-7 w-7 p-0 text-destructive" onClick={() => deleteRule.mutate(rule.id)}>
              <Trash2 className="w-3 h-3" />
            </Button>
          </div>
        ))}
      </div>

      <Dialog open={showBuilder} onOpenChange={(o) => { if (!o) { setShowBuilder(false); resetForm(); } }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="text-sm">{editingRule ? 'Edit Rule' : 'Create Rule'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Rule name</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} className="text-xs h-8" placeholder="e.g. Auto-assign on review" />
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">If this happens…</Label>
              <Select value={triggerType} onValueChange={(v) => { setTriggerType(v); setTriggerConfig({}); }}>
                <SelectTrigger className="text-xs h-8"><SelectValue placeholder="Select trigger" /></SelectTrigger>
                <SelectContent>
                  {TRIGGER_TYPES.map((t) => (
                    <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {triggerType === 'task_assigned' && (
                <Select value={triggerConfig.user_id || ''} onValueChange={(v) => setTriggerConfig({ user_id: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select user" /></SelectTrigger>
                  <SelectContent>
                    {members.map((m) => <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
              {triggerType === 'task_moved' && (
                <Select value={triggerConfig.column || ''} onValueChange={(v) => setTriggerConfig({ column: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select column" /></SelectTrigger>
                  <SelectContent>
                    {COLUMNS.map((c) => <SelectItem key={c.id} value={c.id}>{c.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
              {triggerType === 'tag_added' && (
                <Select value={triggerConfig.tag_id || ''} onValueChange={(v) => setTriggerConfig({ tag_id: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select tag" /></SelectTrigger>
                  <SelectContent>
                    {tags.map((t) => <SelectItem key={t.id} value={t.id}>#{t.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
            </div>

            <div className="space-y-1">
              <Label className="text-[10px] text-muted-foreground">Then do this…</Label>
              <Select value={actionType} onValueChange={(v) => { setActionType(v); setActionConfig({}); }}>
                <SelectTrigger className="text-xs h-8"><SelectValue placeholder="Select action" /></SelectTrigger>
                <SelectContent>
                  {ACTION_TYPES.map((a) => (
                    <SelectItem key={a.value} value={a.value}>{a.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {actionType === 'assign_user' && (
                <Select value={actionConfig.user_id || ''} onValueChange={(v) => setActionConfig({ user_id: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select user" /></SelectTrigger>
                  <SelectContent>
                    {members.map((m) => <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
              {actionType === 'move_to_column' && (
                <Select value={actionConfig.column || ''} onValueChange={(v) => setActionConfig({ column: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select column" /></SelectTrigger>
                  <SelectContent>
                    {COLUMNS.map((c) => <SelectItem key={c.id} value={c.id}>{c.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
              {actionType === 'add_tag' && (
                <Select value={actionConfig.tag_id || ''} onValueChange={(v) => setActionConfig({ tag_id: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select tag" /></SelectTrigger>
                  <SelectContent>
                    {tags.map((t) => <SelectItem key={t.id} value={t.id}>#{t.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
              {actionType === 'send_notification' && (
                <Select value={actionConfig.user_id || ''} onValueChange={(v) => setActionConfig({ user_id: v })}>
                  <SelectTrigger className="text-xs h-8 mt-1"><SelectValue placeholder="Select user" /></SelectTrigger>
                  <SelectContent>
                    {members.map((m) => <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              )}
            </div>

            <div className="flex gap-2 pt-2">
              <Button size="sm" className="flex-1 text-xs" onClick={handleSave}>
                {editingRule ? 'Update Rule' : 'Create Rule'}
              </Button>
              <Button size="sm" variant="outline" className="flex-1 text-xs" onClick={() => { setShowBuilder(false); resetForm(); }}>
                Cancel
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
