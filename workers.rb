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

class UpdateWorker
  include SuckerPunch::Job

  def perform(job, client, records, state)
    Item.where(sfdc_id: records).each do |item|
      curr_obj = Restforce::SObject.build(JSON.parse(item.obj_hash), client)
      result = update_object(client, curr_obj, state)
      item.update(status: state) if result
    end
    update_job(job)
  end

  def update_object(client, object, state)
    raise NotImplementedError
  end

  def update_job(job)
    raise NotImplementedError
  end
end

class UpdateWorkflowRuleWorker < UpdateWorker
  def update_object(client, object, state)
    state_bool = state == 'active' ? true : false
    client.update('WorkflowRule', Id: object.Id, Metadata: {  actions: object.Metadata['actions'],
                                                             active: state_bool,
                                                             booleanFilter: object.Metadata['booleanFilter'],
                                                             criteriaItems: object.Metadata['criteriaItems'],
                                                             description: object.Metadata['description'],
                                                             formula: object.Metadata['formula'],
                                                             fullName: object.Metadata['fullName'],
                                                             triggerType: object.Metadata['triggerType'],
                                                             workflowTimeTriggers: object.Metadata['workflowTimeTriggers'] })
  end

  def update_job(job)
    job[:wr_status] = 'Complete'
    job.save
  end
end

class UpdateValidationRuleWorker < UpdateWorker
  def update_object(client, object, state)
    state_bool = state == 'active' ? true : false
    client.update!('ValidationRule', Id: object.Id, Metadata: { active: state_bool,
                                                                description: object.Metadata['description'],
                                                                errorConditionFormula: object.Metadata['errorConditionFormula'],
                                                                errorDisplayField: object.Metadata['errorDisplayField'],
                                                                errorMessage: object.Metadata['errorMessage'],
                                                                fullName: object.Metadata['fullName'] })
  end

  def update_job(job)
    job[:vr_status] = 'Complete'
    job.save
  end
end

class UpdateProcessBuilderWorker < UpdateWorker
  def update_object(client, object, state)
    avn = state == 'active' ? object.VersionNumber : 0
    client.update!('FlowDefinition', Id: object.DefinitionId, Metadata: { activeVersionNumber: avn })
  end

  def update_job(job)
    job[:pb_status] = 'Complete'
    job.save
  end
end
