_          = require 'lodash'
async      = require 'async'
debug      = require('debug')('nanocyte-interval-service:register-job-processor')
cronParser = require 'cron-parser'
{Stats}    = require 'fast-stats'

class RegisterJobProcessor
  constructor: (options) ->
    {@client,@kue,@queue,@pingInterval,@intervalAttempts,@intervalTTL,@minTimeDiff} = options

  processJob: (job, ignore, callback) =>
    debug 'processing register job', job.id, 'data', JSON.stringify job.data
    async.series [
      async.apply @doUnregister, job.data
      async.apply @removeDisabledKey, job.data
      async.apply @createIntervalProperties, job.data
      async.apply @createIntervalJob, job.data
      async.apply @createPingJob, job.data
    ], callback

  createPingJob: (data, callback) =>
    {sendTo, nodeId} = data
    job = @queue.create('ping', data)
      .delay(@pingInterval)
      .removeOnComplete(true)
      .save (error) =>
        return callback error if error?
        @client.set "interval/ping/#{sendTo}/#{nodeId}", job.id, callback

  createIntervalJob: (data, callback) =>
    {cronString, sendTo, nodeId, intervalTime} = data
    if cronString?
      try
        intervalTime = @calculateNextCronInterval cronString
        @client.set "interval/time/#{sendTo}/#{nodeId}", intervalTime
      catch error
        console.error error
        return callback()

    data.intervalTime = intervalTime

    return callback new Error "invalid intervalTime: #{intervalTime}" unless intervalTime >= 1000

    job = @queue.create('interval', data)
      .delay(intervalTime)
      .removeOnComplete(true)
      .attempts(@intervalAttempts)
      .ttl(@intervalTTL)
      .save (error) =>
        return callback error if error?
        async.series [
          async.apply @client.del, "interval/job/#{sendTo}/#{nodeId}"
          async.apply @client.sadd, "interval/job/#{sendTo}/#{nodeId}", job.id
        ], callback

  createIntervalProperties: (data, callback) =>
    {sendTo, nodeId, intervalTime, cronString, nonce} = data
    @client.mset "interval/active/#{sendTo}/#{nodeId}", 'true',
      "interval/time/#{sendTo}/#{nodeId}", intervalTime || '',
      "interval/cron/#{sendTo}/#{nodeId}", cronString || '',
      "interval/nonce/#{sendTo}/#{nodeId}", nonce || ''
    , callback

  calculateNextCronInterval: (cronString, currentDate) =>
    currentDate ?= new Date
    timeDiff = 0
    parser = cronParser.parseExpression cronString, currentDate: currentDate

    while timeDiff <= @minTimeDiff
      nextDate = parser.next()
      nextDate.setMilliseconds 0
      timeDiff = nextDate - currentDate

    return timeDiff

  removeDisabledKey: ({sendTo,nodeId}, callback) =>
    @client.del 'ping:disabled', "#{sendTo}:#{nodeId}", callback

  doUnregister: ({sendTo, nodeId}, callback) =>
    async.series [
      async.apply @removeIntervalProperties, {sendTo, nodeId}
      async.apply @removeIntervalJobs, {sendTo, nodeId}
      async.apply @removePingJob, {sendTo, nodeId}
    ], callback

  removeIntervalProperties: ({sendTo, nodeId}, callback) =>
      @client.del "interval/active/#{sendTo}/#{nodeId}",
      "interval/time/#{sendTo}/#{nodeId}",
      "interval/cron/#{sendTo}/#{nodeId}",
      "interval/nonce/#{sendTo}/#{nodeId}", callback

  removeIntervalJobs: ({sendTo, nodeId}, callback) =>
    @client.smembers "interval/job/#{sendTo}/#{nodeId}", (error, jobIds) =>
      return callback error if error?
      async.each jobIds, @removeJob, callback

  removePingJob: ({sendTo, nodeId}, callback) =>
    @client.get "interval/ping/#{sendTo}/#{nodeId}", (error, jobId) =>
      return callback error if error?
      @removeJob jobId, callback

  removeJob: (jobId, callback) =>
    @kue.Job.get jobId, (error, job) =>
      job.remove() unless error?
      callback()

module.exports = RegisterJobProcessor