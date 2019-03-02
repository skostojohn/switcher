class FetchWorker
  include SuckerPunch::Job

  def perform(job, client, object)
    item_ids = get_ids(client, object)
    item_ids.each do |item_id|
      curr_item = get_item(client, item_id)
      next unless active?(curr_item, object)

      db_item = create_db_item(job, curr_item)
      db_item.save
    end
    update_job(job)
  end

  private
  def get_ids(client, object)
    raise NotImplementedError
  end

  def get_item(client, item_id)
    raise NotImplementedError
  end

  def active?(item, object)
    raise NotImplementedError
  end

  def create_db_item(job, item)
    raise NotImplementedError
  end

  def update_job(job)
    raise NotImplementedError
  end
end

class FetchWorkflowRuleWorker < FetchWorker
  def get_ids(client, object)
    client.query("select id from workflowrule where tableenumorid = '#{object}'")
  end

  def get_item(client, item_id)
    client.find('WorkflowRule', item_id.Id)
  end

  def active?(item, object)
    item.Metadata['active']
  end

  def create_db_item(job, item)
    Item.new(type: 'WorkflowRule', job_id: job.id, sfdc_id: item.Id, created: DateTime.now,
             name: item.Name, obj_hash: item.to_hash.to_json, status: 'active')
  end

  def update_job(job)
    job[:wr_status] = 'Complete'
    job.save
  end
end

class FetchValidationRuleWorker < FetchWorker
  def get_ids(client, object)
    client.query("select id from validationrule where entitydefinitionid = '#{object}'")
  end

  def get_item(client, item_id)
    client.find('ValidationRule', item_id.Id)
  end

  def active?(item, object)
    item.Metadata['active']
  end

  def create_db_item(job, item)
    Item.new(type: 'ValidationRule', job_id: job.id, sfdc_id: item.Id, created: DateTime.now,
      name: item.ValidationName, obj_hash: item.to_hash.to_json, status: 'active')
  end

  def update_job(job)
    job[:vr_status] = 'Complete'
    job.save
  end
end

class FetchProcessBuilderWorker < FetchWorker
  def get_ids(client, object)
    client.query('select Id, ActiveVersionId from FlowDefinition where ActiveVersionId != null')
  end

  def get_item(client, item_id)
    client.find('Flow', item_id.ActiveVersionId)
  end

  def active?(item, object)
    item.Metadata['processType'] == 'Workflow' && item.Metadata['processMetadataValues'].select { |x| x.name == 'ObjectType' }[0]['value']['stringValue'] == object
  end

  def create_db_item(job, item)
    Item.new(type: 'ProcessBuilder', job_id: job.id, sfdc_id: item.Id, created: DateTime.now,
             name: item.Metadata['label'], obj_hash: item.to_hash.to_json, status: 'active')
  end

  def update_job(job)
    job[:pb_status] = 'Complete'
    job.save
  end
end

class UpdateWorkflowRuleWorker
  include SuckerPunch::Job

  def perform(job, client, records, state)
    state_bool = state == 'active' ? true : false
    Item.where(sfdc_id: records).each do |item|
      wrule = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      result = client.update('WorkflowRule', Id: wrule.Id, Metadata: {  actions: wrule.Metadata['actions'],
                                                                        active: state_bool,
                                                                        booleanFilter: wrule.Metadata['booleanFilter'],
                                                                        criteriaItems: wrule.Metadata['criteriaItems'],
                                                                        description: wrule.Metadata['description'],
                                                                        formula: wrule.Metadata['formula'],
                                                                        fullName: wrule.Metadata['fullName'],
                                                                        triggerType: wrule.Metadata['triggerType'],
                                                                        workflowTimeTriggers: wrule.Metadata['workflowTimeTriggers'] })
      item.update(status: state) if result
    end
    job[:wr_status] = 'Complete'
    job.save
  end
end

class UpdateValidationRuleWorker
  include SuckerPunch::Job

  def perform(job, client, records, state)
    state_bool = state == 'active' ? true : false
    Item.where(sfdc_id: records).each do |item|
      vrule = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      result = client.update!('ValidationRule', Id: vrule.Id, Metadata: { active: state_bool,
                                                description: vrule.Metadata['description'],
                                                errorConditionFormula: vrule.Metadata['errorConditionFormula'],
                                                errorDisplayField: vrule.Metadata['errorDisplayField'],
                                                errorMessage: vrule.Metadata['errorMessage'],
                                                fullName: vrule.Metadata['fullName'] })
      item.update(status: state) if result
    end
    job[:vr_status] = 'Complete'
    job.save
  end
end

class UpdateProcessBuilderWorker
  include SuckerPunch::Job

  def perform(job, client, records, state)
    Item.where(sfdc_id: records).each do |item|
      pb = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      avn = state == 'active' ? pb.VersionNumber : 0
      result = client.update!('FlowDefinition', Id: pb.DefinitionId, Metadata: { activeVersionNumber: avn })
      item.update(status: state) if result
    end
    job[:pb_status] = 'Complete'
    job.save
  end
end